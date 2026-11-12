# IDs: AC-LOGIN-3 AC-LOGIN-7
"""Start the device-code sign-in on the iPad (Account screen) and print the code. The app then polls by itself."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tb import App, shot
a = App()
time.sleep(2)
st = a.j("state")
if st["signed_in"]:
    print(json.dumps({"signed_in": True}))
    sys.exit(0)
a.cmd("orient 1")
r = a.j("signin")
time.sleep(1.5)
shot("look_port_signin")
print("SIGNIN", json.dumps(r))
