' Start a console program with no window, and let it outlive whoever started it.
'
' Why this file exists. The shadow runner has to survive the hook process exiting, and on
' Windows that needs spawn(detached). But detached gives the child its own console, which
' overrides Node's windowsHide - so every prompt flashed a pwsh window on screen. Measured, in
' this order: a plain spawn (hidden, no console) dies with the parent; `cmd /c start /b` and
' `detached` both survive but flash; wscript is a GUI-subsystem host with no console of its own,
' so it survives and has nothing to flash. It then starts the real program hidden.
'
' Usage:  wscript //B //Nologo shadow-hidden-launch.vbs <program> <arg> <arg> ...

Dim shell, command, i
Set shell = CreateObject("WScript.Shell")
command = ""
For i = 0 To WScript.Arguments.Count - 1
  command = command & """" & WScript.Arguments(i) & """ "
Next
' 0 = hidden window, False = do not wait for it to finish.
shell.Run command, 0, False
