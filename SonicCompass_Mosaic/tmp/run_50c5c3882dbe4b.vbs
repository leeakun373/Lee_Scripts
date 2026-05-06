Set s = WScript.CreateObject("WScript.Shell")
s.Run "cmd /C curl -s --max-time 3 ""http://127.0.0.1:18765/api/mosaic/health"" > ""C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\res_50c5c3882dbe4b.json"" 2>NUL & echo 1 > ""C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\done_50c5c3882dbe4b.flag""", 0, True
