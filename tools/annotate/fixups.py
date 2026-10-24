import sys

p = sys.argv[1]
s = open(p).read()
reps = [
    ("  mov   #%10100010, ocr ; 5KHz, RC off\n  mov   #$00, BatteryCheck",
     "  mov   #%10100011, ocr                 ; OCR $A3: back to the 32kHz quartz, RC + CF stopped\n  mov   #$00, BatteryCheck"),
    (""" ;; NOTE: in the ROM, P3Isr stores the PREVIOUS state at $72 and the newly-pressed
 ;; mask at $71 (BaseTimerIsr also writes the previous state to $72). These two
 ;; definitions are swapped relative to that, so the P3Isr lines using them do not
 ;; assemble to the original bytes.
Buttons_Last     = $71
Buttons_Diff     = $72
""", """Buttons_Diff     = $71   ; buttons newly pressed since the last P3 interrupt
Buttons_Last     = $72   ; previous Buttons_Current (also written by BaseTimerIsr)
"""),
(";; NOTE: see the Buttons_Last / Buttons_Diff definitions at the end of the file.\n", ""),
    ("previous state -> $72 (see the note at Buttons_Last), clear Buttons_Current",
     "previous state -> Buttons_Last, clear Buttons_Current"),
    ("  st    $72\n  mov   #$00, Buttons_Current", "  st    Buttons_Last\n  mov   #$00, Buttons_Current"),
]
for a, b in reps:
    if s.count(a) != 1:
        raise SystemExit('fixup not found exactly once: ' + a[:60])
    s = s.replace(a, b)
open(p, 'w').write(s)
