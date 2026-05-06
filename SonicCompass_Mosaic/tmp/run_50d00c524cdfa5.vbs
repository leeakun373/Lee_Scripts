On Error Resume Next
Set s = WScript.CreateObject("WScript.Shell")
s.Run "cmd /C curl -s --max-time 3 ""http://127.0.0.1:18765/api/mosaic/health"" > ""C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\res_50d00c524cdfa5.json"" 2>NUL & echo 1 > ""C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\done_50d00c524cdfa5.flag""", 0, True
