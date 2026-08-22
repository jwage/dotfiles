#include "globals.hpp"
#include "kinetic.hpp"
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/devices/IPointer.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/config/values/types/FloatValue.hpp>
#include <hyprland/src/config/values/types/IntValue.hpp>
#include <hyprland/src/config/values/types/StringValue.hpp>
#include <fstream>
#include <sstream>
#include <vector>
#include <cstddef>
#include <limits>
#include <stdexcept>

extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

// LOCAL PATCH (not upstream): make the `debug` default settable at build time.
//
// This plugin's debug log is the only window into why a gesture did or did not
// glide, and on Hyprland 0.56.2 there is no way to turn it on at runtime.
// `hyprctl keyword plugin:...` refuses plugin-registered keys outright ("can't
// work with non-legacy parsers"), and the Lua config validator rejects them
// too, from both the nested `plugin = {}` form and the flat string-key form --
// so neither hypr/input.lua nor `hyprctl eval` can reach it. That leaves
// rebuilding as the only switch, which is why this is a compile-time default
// rather than the usual config value. `build.sh --debug` sets it; a plain
// `build.sh` leaves it off so the installed plugin does not append to
// /tmp/hypr-kinetic-scroll.log on every scroll event forever.
#ifndef KINETIC_DEBUG_DEFAULT
#define KINETIC_DEBUG_DEFAULT 0
#endif

static Hyprutils::Signal::CHyprSignalListener g_pAxisCallback;
static Hyprutils::Signal::CHyprSignalListener g_pButtonCallback;
static Hyprutils::Signal::CHyprSignalListener g_pWindowCallback;
static Hyprutils::Signal::CHyprSignalListener g_pConfigReloadCallback;
static std::vector<Hyprutils::Signal::CHyprSignalListener> g_pTouchpadCallbacks;

static void refreshTouchpadCallbacks();

static void onMouseAxis(const IPointer::SAxisEvent& e, Event::SCallbackInfo& /*info*/) {
    if (!g_pKineticState)
        return;

    // See refreshTouchpadCallbacks(): the touchpads we need to hook usually do
    // not exist yet when this plugin is initialised, so the hooks are (re)built
    // here, from the one event that is guaranteed to be delivered device-
    // agnostically.
    refreshTouchpadCallbacks();

    auto event = e;
    g_pKineticState->onAxis(event);
    // Don't cancel - let the original scroll event pass through to the app
}

static void onMouseButton(const IPointer::SButtonEvent& e, Event::SCallbackInfo& /*info*/) {
    if (!g_pKineticState)
        return;

    if (!getKineticConfigInt("stop_on_click", 0))
        return;

    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED)
        return;
    if (getKineticConfigInt("debug", 0)) {
        std::ofstream log("/tmp/hypr-kinetic-scroll.log", std::ios::app);
        if (log.is_open())
            log << "[hypr-kinetic-scroll] mouseButton -> stopKinetic\n";
    }

    // Any mouse click stops kinetic scrolling
    g_pKineticState->stopKinetic("mouseButton");
}

static void onActiveWindow() {
    if (!g_pKineticState)
        return;

    if (!getKineticConfigInt("stop_on_focus", 0))
        return;

    if (getKineticConfigInt("debug", 0)) {
        std::ofstream log("/tmp/hypr-kinetic-scroll.log", std::ios::app);
        if (log.is_open())
            log << "[hypr-kinetic-scroll] activeWindow -> stopKinetic\n";
    }

    // Window focus change stops kinetic scrolling
    g_pKineticState->stopKinetic("activeWindow");
}

static void onConfigPreReload() {
    if (g_pKineticState)
        g_pKineticState->resetAppRules();
}

static Hyprlang::CParseResult parseKineticScrollRule(const char* /*command*/, const char* value) {
    Hyprlang::CParseResult result;
    std::istringstream     iss(value ? value : "");
    std::string            mode, appClass;

    if (!(iss >> mode)) {
        result.setError("Invalid format: expected 'enable [class]' or 'disable [class]'");
        return result;
    }

    bool enable = true;
    if (mode == "disable")
        enable = false;
    else if (mode != "enable") {
        result.setError("Invalid mode: expected 'enable' or 'disable'");
        return result;
    }

    if (!(iss >> appClass)) {
        g_pKineticState->setDefaultAppRule(enable);
        return result;
    }

    std::string extra;
    if (iss >> extra) {
        result.setError("Invalid format: expected 'enable [class]' or 'disable [class]'");
        return result;
    }

    g_pKineticState->setAppRule(appClass, enable);
    return result;
}

static int luaSetAppRule(lua_State* L, bool enabled) {
    const char* appClass = luaL_checkstring(L, 1);
    if (g_pKineticState)
        g_pKineticState->setAppRule(appClass, enabled);
    return 0;
}

static int luaEnable(lua_State* L) {
    return luaSetAppRule(L, true);
}

static int luaDisable(lua_State* L) {
    return luaSetAppRule(L, false);
}

static int luaEnableDefault(lua_State* /*L*/) {
    if (g_pKineticState)
        g_pKineticState->setDefaultAppRule(true);
    return 0;
}

static int luaDisableDefault(lua_State* /*L*/) {
    if (g_pKineticState)
        g_pKineticState->setDefaultAppRule(false);
    return 0;
}

static int luaResetRules(lua_State* /*L*/) {
    if (g_pKineticState)
        g_pKineticState->resetAppRules();
    return 0;
}

static void registerLuaFunctions() {
    HyprlandAPI::addLuaFunction(PHANDLE, "kinetic_scroll", "enable", luaEnable);
    HyprlandAPI::addLuaFunction(PHANDLE, "kinetic_scroll", "disable", luaDisable);
    HyprlandAPI::addLuaFunction(PHANDLE, "kinetic_scroll", "enable_default", luaEnableDefault);
    HyprlandAPI::addLuaFunction(PHANDLE, "kinetic_scroll", "disable_default", luaDisableDefault);
    HyprlandAPI::addLuaFunction(PHANDLE, "kinetic_scroll", "reset_rules", luaResetRules);
}

static void registerConfigValues() {
    using namespace Config::Values;
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:enabled", "Enable kinetic scrolling", 1));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CFloatValue>("plugin:kinetic-scroll:decel", "Kinetic deceleration multiplier", 0.92F));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CFloatValue>("plugin:kinetic-scroll:min_velocity", "Minimum velocity before stopping", 0.5F));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:interval_ms", "Kinetic timer interval", 16));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CFloatValue>("plugin:kinetic-scroll:delta_multiplier", "Scroll delta multiplier", 1.25F));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:disable_in_browser", "Disable kinetic scrolling in browsers", 1));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:stop_on_target_change", "Stop inertia when scroll target changes", 1));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CStringValue>("plugin:kinetic-scroll:disabled_classes", "Comma or space separated classes with kinetic scrolling disabled", ""));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:debug", "Enable kinetic scroll debug logging", KINETIC_DEBUG_DEFAULT));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:stop_on_click", "Stop inertia on mouse click", 0));
    HyprlandAPI::addConfigValueV2(PHANDLE, makeShared<CIntValue>("plugin:kinetic-scroll:stop_on_focus", "Stop inertia on focus change", 0));
}

// LOCAL PATCH (not upstream). Upstream registered these hooks exactly once,
// from PLUGIN_INIT. That works when the plugin is loaded by hand with
// `hyprctl plugin load`, and never works when it is loaded from the config.
//
// Hyprland enumerates input devices *after* it parses the config, and
// `hl.plugin.load()` in hypr/input.lua runs during that parse. So at
// PLUGIN_INIT g_pInputManager->m_pointers is still empty, the loop below found
// nothing, and not a single touchpad got hooked. That is fatal to the whole
// feature rather than a partial degradation: the per-device `frame` signal is
// the only way to observe the axis-less frame libinput sends when the fingers
// lift, so without it onPointerFrame() never runs, m_cancelOnStopTimer is never
// cleared, and every gesture ends in stopKinetic("gestureIdle") instead of
// momentum. Scrolling still worked -- it just never glided, which is exactly
// the symptom that looked like a tuning problem.
//
// Rescanning has a second payoff. A touchpad that appears later now gets
// hooked too, which this machine depends on: magicmouse-scroll's virtual
// touchpad is created by a user service that starts after the compositor, and
// a Bluetooth touchpad can come and go at any time.
//
// The whole listener vector is rebuilt rather than diffed against a remembered
// set, because IPointer objects are freed when a device disconnects -- a
// remembered raw address could dangle and then be reused by a new device,
// which would silently skip hooking it. Rebuilding is only safe because this
// runs from the *global* axis event; calling it from one of the per-device
// callbacks below would free the listener that is currently executing.
static size_t g_lastPointerCount = std::numeric_limits<size_t>::max();

static void refreshTouchpadCallbacks() {
    if (!g_pInputManager)
        return;

    // Cheap guard: this is called on every scroll event, and the device list
    // only changes on hotplug.
    const size_t pointerCount = g_pInputManager->m_pointers.size();
    if (pointerCount == g_lastPointerCount)
        return;
    g_lastPointerCount = pointerCount;

    g_pTouchpadCallbacks.clear();

    for (const auto& pointer : g_pInputManager->m_pointers) {
        if (!pointer || !pointer->m_isTouchpad)
            continue;

        g_pTouchpadCallbacks.emplace_back(pointer->m_pointerEvents.frame.listen([] {
            if (g_pKineticState)
                g_pKineticState->onPointerFrame();
        }));
        g_pTouchpadCallbacks.emplace_back(pointer->m_pointerEvents.motion.listen([](const IPointer::SMotionEvent&) {
            if (g_pKineticState)
                g_pKineticState->onTouchpadContact();
        }));
        g_pTouchpadCallbacks.emplace_back(pointer->m_pointerEvents.holdBegin.listen([](const IPointer::SHoldBeginEvent&) {
            if (g_pKineticState)
                g_pKineticState->onTouchpadContact();
        }));
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    PHANDLE = handle;

    // Upstream ships this version check commented out, and it has to stay that
    // way here. Re-enabling it was tried on 2026-08-22 and the plugin then
    // refused to load on a build made against this exact machine's installed
    // headers:
    //
    //   plugin crashed/threw in main: built against a different Hyprland ABI
    //
    // So the hash is not a usable proxy for ABI compatibility on Arch's
    // packaged Hyprland -- __hyprland_api_get_hash() (baked into the headers)
    // and __hyprland_api_get_client_hash() (baked into the running binary) do
    // not agree even when both come from the same hyprland package. Turning it
    // on does not buy safety, it just guarantees the plugin never loads.
    //
    // The real protection against an ABI mismatch is therefore procedural:
    // re-run build.sh after a Hyprland upgrade. A plugin that is genuinely
    // stale will fail at a symbol instead, which is the risk being accepted
    // here -- see the crash note in README.md.
    // if (__hyprland_api_get_hash() != __hyprland_api_get_client_hash())
    //     throw std::runtime_error("Version mismatch");

    registerConfigValues();

    // Create kinetic state (must be before registering keyword so it's available during config parse)
    g_pKineticState = new KineticState();

    HyprlandAPI::addConfigKeyword(PHANDLE, "kinetic-scroll-rule", parseKineticScrollRule, {});
    registerLuaFunctions();

    // Register event callbacks
    g_pAxisCallback = Event::bus()->m_events.input.mouse.axis.listen(onMouseAxis);
    g_pButtonCallback = Event::bus()->m_events.input.mouse.button.listen(onMouseButton);
    g_pWindowCallback = Event::bus()->m_events.window.active.listen(onActiveWindow);
    g_pConfigReloadCallback = Event::bus()->m_events.config.preReload.listen(onConfigPreReload);
    refreshTouchpadCallbacks();

    return {"hypr-kinetic-scroll", "Kinetic (inertial) scrolling for touchpads", "savonovv", "0.1"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    // Release callback refs (Hyprland auto-cleans registered callbacks on plugin unload,
    // but resetting our SPs ensures deterministic ordering)
    g_pAxisCallback.reset();
    g_pButtonCallback.reset();
    g_pWindowCallback.reset();
    g_pConfigReloadCallback.reset();
    g_pTouchpadCallbacks.clear();
    g_lastPointerCount = std::numeric_limits<size_t>::max();

    // Clean up kinetic state (removes wl timers)
    delete g_pKineticState;
    g_pKineticState = nullptr;
}
