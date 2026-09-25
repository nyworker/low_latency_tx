#!/usr/bin/env python3
"""Small always-visible window showing local PC time with milliseconds."""

import ctypes
import os
import sys
from datetime import datetime

# GTK4 has no keep-above API and Wayland has no client-side "always on top",
# so run through XWayland and ask the window manager via _NET_WM_STATE.
os.environ.setdefault("GDK_BACKEND", "x11")

import gi

gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib  # noqa: E402

FONT_SIZE = 28          # pt


class _XClientMessage(ctypes.Structure):
    _fields_ = [
        ("type", ctypes.c_int), ("serial", ctypes.c_ulong),
        ("send_event", ctypes.c_int), ("display", ctypes.c_void_p),
        ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
        ("format", ctypes.c_int), ("data", ctypes.c_long * 5),
        ("pad", ctypes.c_long * 19),
    ]


def set_above(xid, on):
    """Set/clear _NET_WM_STATE_ABOVE on an X11 window."""
    x = ctypes.CDLL("libX11.so.6")
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XOpenDisplay.argtypes = [ctypes.c_char_p]
    x.XInternAtom.restype = ctypes.c_ulong
    x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int,
                             ctypes.c_long, ctypes.c_void_p]
    x.XFlush.argtypes = [ctypes.c_void_p]
    x.XCloseDisplay.argtypes = [ctypes.c_void_p]
    dpy = x.XOpenDisplay(None)
    if not dpy:
        return
    ev = _XClientMessage()
    ev.type = 33  # ClientMessage
    ev.send_event = 1
    ev.display = dpy
    ev.window = xid
    ev.message_type = x.XInternAtom(dpy, b"_NET_WM_STATE", 0)
    ev.format = 32
    ev.data[0] = 1 if on else 0  # _NET_WM_STATE_ADD / REMOVE
    ev.data[1] = x.XInternAtom(dpy, b"_NET_WM_STATE_ABOVE", 0)
    ev.data[3] = 1  # source: normal application
    x.XSendEvent(dpy, x.XDefaultRootWindow(dpy), 0,
                 (1 << 20) | (1 << 19), ctypes.byref(ev))  # Redirect|Notify
    x.XFlush(dpy)
    x.XCloseDisplay(dpy)


class ClockWindow(Gtk.ApplicationWindow):
    def __init__(self, app, show_date):
        super().__init__(application=app, title="PC Clock")
        self.show_date = show_date
        self.set_default_size(320, 90)
        self.set_resizable(False)
        self.set_decorated(True)
        header = Gtk.HeaderBar()
        self.pin = Gtk.ToggleButton(icon_name="view-pin-symbolic")
        self.pin.set_tooltip_text("Always on top")
        self.pin.connect("toggled", self.on_pin)
        header.pack_start(self.pin)
        self.set_titlebar(header)

        self.label = Gtk.Label()
        self.label.add_css_class("clock")
        self.label.set_margin_top(10)
        self.label.set_margin_bottom(10)
        self.label.set_margin_start(16)
        self.label.set_margin_end(16)
        self.label.set_justify(Gtk.Justification.CENTER)
        self.set_child(self.label)

        css = Gtk.CssProvider()
        css.load_from_data(
            (
                f"label.clock {{ font-family: monospace; font-size: {FONT_SIZE}pt; }}"
                "headerbar { min-height: 0; padding: 0; }"
                "headerbar windowhandle, headerbar box { min-height: 0; }"
                "headerbar button { min-height: 0; min-width: 0; padding: 0 4px; margin: 0; }"
            ).encode()
        )
        Gtk.StyleContext.add_provider_for_display(
            self.get_display(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        self.tick()
        # Update on every frame (vsync) so the clock is as fresh as the display allows.
        self.add_tick_callback(lambda *_: self.tick())

    def on_pin(self, button):
        surface = self.get_surface()
        if hasattr(surface, "get_xid"):
            set_above(surface.get_xid(), button.get_active())

    def tick(self):
        now = datetime.now()
        text = now.strftime("%H:%M:%S.") + f"{now.microsecond // 100000:01d}"
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
