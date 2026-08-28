#!/usr/bin/env python3
"""Set how much ground an arriving notification paints over its own blur.

    apply-notification-opacity.py CONF_DIR PERCENT

One number for three rules, because they are one ladder rather than three
independent choices. css/shell-notification-blur.css paints the banner at rest,
on hover and while pressed, and the two steps above rest are what make a hover
read as a hover — the surface has to get *more* solid under the pointer, not
less, or the feedback runs backwards. So the percentage sets the resting ground
and the steps ride on top of it at the offsets the sheet was tuned with,
+0.08 then +0.06.

Only the alpha moves. The colour is the shell tint's business
(tools/apply-shell-tint.py), and the two rewriters are ordered so that this one
can run either side of it: the tint reads a literal's channels and rewrites
them, this one reads its alpha and rewrites that, and neither looks at what the
other owns.

Clamped so the ladder cannot invert or saturate: the resting ground is held
inside the bounds install.sh checks, and the two steps above it stop at 0.95
rather than running past 1.0, which would flatten hover and pressed into the
same fully opaque surface.

Run against the installed copy in $CONF_DIR. install_css lays that down fresh
from css/ on every run, so this never compounds and css/ stays at the one state
tools/check-tokens.sh checks. The sheet is absent whenever notification blur is
off, and an absent sheet is nothing to rewrite rather than an error — there is
no blur behind a banner to tune the ground against.
"""
import os
import re
import sys

SHEET = "shell-notification-blur.css"

# Each rule, and how far its ground sits above the resting one. The selectors
# are matched in full rather than by their alpha, so a run cannot land on the
# history cards' literals — those are a separate ladder this number does not
# speak for, and they are matched by .message alone.
RULES = [
    (r"(\.message\.notification-banner \{\n"
     r"  background-color: rgba\(\d+, \d+, \d+, )([0-9.]+)", 0.00),
    (r"(\.message\.notification-banner:hover,\n"
     r"\.message\.notification-banner:focus \{\n"
     r"  background-color: rgba\(\d+, \d+, \d+, )([0-9.]+)", 0.08),
    (r"(\.message\.notification-banner:active \{\n"
     r"  background-color: rgba\(\d+, \d+, \d+, )([0-9.]+)", 0.14),
]

CEILING = 0.95


def main():
    if len(sys.argv) != 3:
        print("usage: apply-notification-opacity.py CONF_DIR PERCENT",
              file=sys.stderr)
        return 2
    conf, percent = sys.argv[1], sys.argv[2].strip()

    if not percent.isdigit():
        print("apply-notification-opacity.py: '%s' is not a whole percentage"
              % percent, file=sys.stderr)
        return 2

    path = os.path.join(conf, SHEET)
    if not os.path.exists(path):
        # Notification blur is off, so there is no sheet and nothing to tune.
        return 0

    rest = int(percent) / 100.0
    text = open(path, encoding="utf-8").read()

    for pattern, step in RULES:
        alpha = min(CEILING, rest + step)
        text, count = re.subn(pattern,
                              lambda m, a=alpha: "%s%.2f" % (m.group(1), a),
                              text, count=1)
        if count != 1:
            print("apply-notification-opacity.py: %s does not have the rule "
                  "this expects — the banner ground is left where it is"
                  % SHEET, file=sys.stderr)
            return 1

    open(path, "w", encoding="utf-8").write(text)
    print("notification ground at %d%% (hover and pressed step up from there)"
          % int(percent))
    return 0


if __name__ == "__main__":
    sys.exit(main())
