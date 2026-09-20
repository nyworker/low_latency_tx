#!/usr/bin/env python3
"""Small always-visible window showing local PC time with milliseconds."""

import sys
from datetime import datetime

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib  # noqa: E402

FONT_SIZE = 28          # pt


class ClockWindow(Gtk.ApplicationWindow):
    def __init__(self, app, show_date):
        super().__init__(application=app, title="PC Clock")
        self.show_date = show_date
        self.set_default_size(320, 90)
        self.set_resizable(True)

        self.label = Gtk.Label()
        self.label.set_margin_top(10)
        self.label.set_margin_bottom(10)
        self.label.set_margin_start(16)
        self.label.set_margin_end(16)
        self.label.set_justify(Gtk.Justification.CENTER)
        self.set_child(self.label)

        # No title bar; drag the clock with the left mouse button to move it.
        self.set_decorated(False)
        drag = Gtk.GestureClick(button=1)
        drag.connect("pressed", self.on_press)
        self.label.add_controller(drag)

        css = Gtk.CssProvider()
        css.load_from_data(
            f"label {{ font-family: monospace; font-size: {FONT_SIZE}pt; }}".encode()
        )
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.tick()
        # Update on every frame (vsync) so the clock is as fresh as the display allows.
        self.add_tick_callback(lambda *_: self.tick())

    def on_press(self, gesture, n_press, x, y):
        event = gesture.get_current_event()
        self.get_surface().begin_move(
            event.get_device(), 1, x, y, event.get_time()
        )

    def tick(self):
        now = datetime.now()
        text = now.strftime("%H:%M:%S.") + f"{now.microsecond // 10000:02d}"
        if self.show_date:
            text = now.strftime("%Y-%m-%d\n") + text
        self.label.set_text(text)
        return GLib.SOURCE_CONTINUE


class ClockApp(Gtk.Application):
    def __init__(self, show_date):
        super().__init__(application_id="local.msclock")
        self.show_date = show_date

    def do_activate(self):
        ClockWindow(self, self.show_date).present()


if __name__ == "__main__":
    show_date = "-d" in sys.argv or "--date" in sys.argv
    sys.exit(ClockApp(show_date).run([sys.argv[0]]))
