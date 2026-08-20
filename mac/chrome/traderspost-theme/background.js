// Applies TradersPost chrome on every install/start. Manifest-only themes often
// look like default gray on current Chrome; the theme API is more reliable.
// Palette: omarchy/themes/traderspost/colors.toml

const tradersPostTheme = {
  colors: {
    frame: [9, 40, 90],
    frame_inactive: [14, 20, 26],
    frame_incognito: [14, 20, 26],
    frame_incognito_inactive: [9, 40, 90],
    background_tab: [14, 20, 26],
    background_tab_inactive: [14, 20, 26],
    toolbar: [9, 132, 227],
    toolbar_button_icon: [255, 255, 255],
    toolbar_field: [21, 31, 39],
    toolbar_field_border: [52, 195, 255],
    toolbar_field_focus: [21, 31, 39],
    toolbar_field_text: [243, 246, 248],
    toolbar_field_text_focus: [255, 255, 255],
    toolbar_text: [255, 255, 255],
    tab_text: [243, 246, 248],
    tab_background_text: [216, 222, 227],
    tab_background_text_inactive: [100, 118, 133],
    bookmark_text: [243, 246, 248],
    button_background: [52, 195, 255],
    control_background: [9, 84, 160],
    ntp_background: [14, 20, 26],
    ntp_text: [243, 246, 248],
    ntp_link: [52, 195, 255],
    ntp_header: [243, 246, 248],
    ntp_section: [9, 84, 160],
    omnibox_background: [21, 31, 39],
    omnibox_text: [243, 246, 248],
    omnibox_selection_background: [9, 132, 227],
    omnibox_results_background: [21, 31, 39],
    omnibox_results_text: [243, 246, 248],
    sidebar_background: [21, 31, 39],
    sidebar_text: [216, 222, 227],
    sidebar_border: [9, 132, 227],
  },
  tints: {
    buttons: [0.58, 1.0, 0.55],
    frame: [0.58, 0.85, 0.45],
    frame_inactive: [0.58, 0.7, 0.35],
    background_tab: [0.58, 0.85, 0.4],
  },
  properties: {
    ntp_background_alignment: "bottom",
    ntp_background_repeat: "no-repeat",
  },
  images: {
    theme_frame: "images/theme_frame.png",
    theme_toolbar: "images/theme_toolbar.png",
    theme_tab_background: "images/theme_tab_background.png",
    theme_ntp_background: "images/ntp_background.png",
  },
};

function applyTheme() {
  chrome.theme.update(tradersPostTheme);
}

chrome.runtime.onInstalled.addListener(applyTheme);
chrome.runtime.onStartup.addListener(applyTheme);
applyTheme();
