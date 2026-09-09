"""The live service: the offline model, served.

  settings  what the environment has to say
  state     tracks and the model, stepped on wall time
  wire      how a map frame is written
  hub       one websocket per client
  service   the poll and epoch loops
  db, auth, security, prefs
  app       the HTTP and websocket surface
"""
