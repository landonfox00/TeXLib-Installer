"""
Silence LaTeXTools' "LaTeXTools cache updated" status-bar message.

LaTeXTools writes every ActivityIndicator to ONE status key,
`_latex_tools_activity` (latextools/utils/activity_indicator.py). The build uses
it for "Building..." (make_pdf.py), and the cache updater that fires on every
save uses it for "Updating LaTeXTools cache" (latextools_cache_listener.py).
Saving to build therefore starts both: the cache thread finishes first, its
finish() overwrites the build text with "LaTeXTools cache updated", and its
erase_status 4s later wipes the slot outright.

The message is hardcoded, so there is no setting to turn it off. Rather than
disable the on-save cache refresh (cache.analysis/bibliography.update_on_save),
which would leave \\ref{ and \\cite{ completions stale for up to cache.life_span,
this swaps a no-op indicator into the cache listener module ONLY. Caching still
runs on every save; it just stops writing to the status bar. make_pdf.py and
system_check.py keep their real indicators.

Lives in its own package because Packages/User has no .python-version and so
runs on the 3.3 plugin host, which cannot import from LaTeXTools (3.8). The
sibling .python-version file puts this on 3.8.

Note: LaTeXTools' plugin.py purges its own submodules from sys.modules when it
reloads, which drops this patch. A LaTeXTools update will bring the message back
until Sublime restarts. That is the intended failure mode -- it fails open and
can never break LaTeXTools itself.
"""


class _SilentActivityIndicator:
    """Same surface as ActivityIndicator, minus every status-bar write."""

    def __init__(self, label=None):
        self.label = label

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        pass

    def start(self):
        pass

    def stop(self):
        pass

    def clear(self):
        pass

    def finish(self, message=None):
        pass

    def set_label(self, label):
        self.label = label


def plugin_loaded():
    try:
        from LaTeXTools.latextools import latextools_cache_listener as listener
    except ImportError as e:
        print("QuietLatextoolsCache: LaTeXTools not importable ({}); "
              "nothing patched.".format(e))
        return

    # update_cache() resolves ActivityIndicator as a module global at call time,
    # so rebinding the name here is enough -- no need to touch the real class.
    listener.ActivityIndicator = _SilentActivityIndicator
    print("QuietLatextoolsCache: cache status messages silenced.")
