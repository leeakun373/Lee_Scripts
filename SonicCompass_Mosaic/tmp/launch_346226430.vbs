Set s = CreateObject("WScript.Shell")
s.Run "cmd /C curl --silent --show-error --max-time 3 """"http://127.0.0.1:18765/api/mosaic/health"""" > """"C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\get_resp_346226428.json"""" 2> """"C:\Users\DELL\AppData\Roaming\REAPER\Scripts\Lee_Scripts\SonicCompass_Mosaic\tmp\get_resp_346226429.err""""", 0, False
