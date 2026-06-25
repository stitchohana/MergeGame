extends Node

# EventBus: Lightweight signal bus for cross-widget action events.
# Data events (grid updates) still flow directly from GridManager to their listeners.

# UI action events
signal button_clicked(button_name: String, metadata: Dictionary)

# Screen lifecycle events
signal screen_change_requested(screen_name: String)

# Popup lifecycle
signal popup_shown(popup_name: String)
signal popup_hidden(popup_name: String)

# Game-specific action events
signal restart_requested()
signal resume_requested()
signal pause_requested()
signal quit_requested()
signal settings_requested()

# Toast notification
signal show_toast(message: String)
