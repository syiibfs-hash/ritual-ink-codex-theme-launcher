Option Explicit

Function Quote(ByVal value)
  Quote = """" & Replace(value, """", "\""") & """"
End Function

If WScript.Arguments.Count < 1 Then
  WScript.Quit 2
End If

Dim shell, scriptPath, command, i, arg
Set shell = CreateObject("WScript.Shell")
scriptPath = WScript.Arguments(0)
command = "powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File " & Quote(scriptPath)

For i = 1 To WScript.Arguments.Count - 1
  arg = WScript.Arguments(i)
  If Left(arg, 1) = "-" And InStr(arg, " ") = 0 Then
    command = command & " " & arg
  Else
    command = command & " " & Quote(arg)
  End If
Next

shell.Run command, 0, False
