extends Spatial


# :TODO:Panthavma:20211230:Rollback lol
# :TODO:Panthavma:20211230:Clean up
# :TODO:Panthavma:20220209:Make SyncManager optional

# :TODO:Panthavma:20220124:Refacto module loading

var initOnReady = true


var _gameState = {}
# :TODO:Panthavma:20220125:Change to a struct (?)
var instancedData = {}
var fighterScripts = []

var instancesRoot

# :TODO:Panthavma:20220207:Move this to relevant parts
const STARTING_POSITION = 20000
const ARENA_SIZE = 150000
const CAMERA_SIZE = 55000

var modules
var physicsModule
const POSITION_SCALE = 0.0001

var useOnline = false
var initError = false

#---------------------------------------------------------------------------------------------------
# Initialize
func Init(battleInitData):
	# 1. Start Init
	Castagne.Log("Init Started")
	
	_gameState = {
		"Players": [],
		"EntitiesToInit": [],
	}
	instancedData = {
		"Players": [],
		"ParsedFighters": [],
		"Entities": {},
	}
	fighterScripts = []
	useOnline = false
	initError = false
	
	# 2. Load map
	# Load maps and music
	#:TODO:Panthavma:20220124:Review the map system, maybe as an entity ?
	var prefabMap = Load(Castagne.data["StagePaths"][battleInitData["map"]])
	var map = prefabMap.instance()
	add_child(map)
	instancedData["map"] = map
	instancesRoot = self
	
	if(initError):
		queue_free()
		Castagne.Error("Initialization failed at the map init stage. Aborting.")
		return
		
	# 3. Prepare the first frame
	
	# :TODO:Panthavma:20220125:Move player & input init elsewhere
	var playerList = ["p1", "p2"]
	for pid in range(playerList.size()):
		var pName = playerList[pid]
		
		# Input init
		var prefabInputProvider = Load(Castagne.data["InputProviders"][battleInitData[pName+"-control-type"]])
		var inputProvider = prefabInputProvider.instance()
		inputProvider.set_name("input-"+str(pName))
		if(useOnline):
			inputProvider.set_network_master(battleInitData[pName+"-onlinepeer"])
		inputProvider.Init(battleInitData[pName+"-control-param"])
		add_child(inputProvider)
		
		var pState = {
			"RawInputs": inputProvider.GetEmptyRawInputData(),
			"Inputs": {},
			"MainEntity": pid,
			"PID": pid,
		}
		var pData = {
			"PID": pid,
			"Name": playerList[pid],
			"PeerID": -1,
			"InputProvider": inputProvider,
		}
		_gameState["Players"].append(pState)
		instancedData["Players"].append(pData)
	
	
	if(initError):
		queue_free()
		Castagne.Error("Initialization failed at the player init stage. Aborting.")
		return
	
	# :TODO:Panthavma:20220124:Allow less modules to be in play
	modules = Castagne.modules
	for module in modules:
		module.engine = self
		module.CopyVariablesGlobal(_gameState)
		module.BattleInit(_gameState, _BuildModuleCallbackData(_gameState), battleInitData)
	
	# :TODO:Panthavma:20220125:Move parsing elsewhere
	for player in instancedData["Players"]:
		# Parse the file
		var characterPath = Castagne.data["CharacterPaths"][battleInitData[player["Name"]]]
		var fighter = Castagne.Parser.CreateFullCharacter(characterPath)
		
		if(fighter == null):
			Castagne.Error("Character "+characterPath+" isn't initialized properly.")
			initError = true
			break
		
		var parsedFighterData = {
			"ID": instancedData["ParsedFighters"].size(),
			"File":characterPath,
			"Character":fighter["Character"],
			"Constants":fighter["Constants"],
			"Variables":fighter["Variables"],
		}
		
		instancedData["ParsedFighters"].append(parsedFighterData)
		fighterScripts.append(fighter["States"])
		
		# Add the entity
		# :TODO:Panthavma:20220125:Move entity setup elsewhere
		
		var eid = _gameState["CurrentEntityID"]
		
		var entityState = {
			"Player": player["PID"],
			"FighterID": parsedFighterData["ID"],
			"EID": eid,
		}
		
		# :TODO:Panthavma:20220125:Need main entity id
		# :TODO:Panthavma:20220125:Variables in init phase
		
		var entityInstanceData = {
		}
		
		_gameState["CurrentEntityID"] += 1
		_gameState[eid] = entityState
		_gameState["EntitiesToInit"].append(eid)
		
		# :TODO:Panthavma:20220125:Move model / anim / sound setup elsewhere
		# Load Model
		var playerModelPrefab = Load(fighter["Character"]["Model"])
		var playerModel = playerModelPrefab.instance()
		var playerAnim = playerModel.get_node(fighter["Character"]["AnimPlayerPath"])
		instancesRoot.add_child(playerModel)
		
		entityInstanceData["Model"] = playerModel
		entityInstanceData["AnimPlayer"] = playerAnim
		entityInstanceData["Root"] = playerModel
		
		instancedData["Entities"][eid] = entityInstanceData
	
	if(initError):
		queue_free()
		Castagne.Error("Initialization failed at the fighter init stage. Aborting.")
		return
	
	# :TODO:Panthavma:20220125:Needed here ? Could make problems
	#UpdateGraphics(_gameState)
	
	Castagne.Log("Init Ended\n----------------")







#-------------------------------------------------------------------------------
# Main Loop

func EngineTick(previousState, playerInputs):
	# 1. Frame and input setup
	var state = previousState.duplicate(true)
	state["TrueFrameID"] += 1
	state["SkipFrame"] = false
	
	for playerIData in instancedData.Players:
		var pid = playerIData["PID"]
		var previousRichInput = state["Players"][pid]["Inputs"]
		var currentRawInput = playerInputs[pid]
		# :TODO:Panthavma:20220126:Need to rework this, some input might be entity specific
		var enrichedInput = playerIData["InputProvider"].EnrichInput(currentRawInput, previousRichInput, state, pid)
		state["Players"][pid]["RawInputs"] = currentRawInput
		state["Players"][pid]["Inputs"] = enrichedInput
	
	# 2. Apply the framestart functions, and check if the frame needs to be skipped
	var moduleCallbackData = _BuildModuleCallbackData(state)
	for m in modules:
		m.FrameStart(state, moduleCallbackData)
	
	if(state["SkipFrame"]):
		return state
	
	state["FrameID"] += 1
	
	# 3. Gather the entities needed for the init phase
	var entitiesToInit = state["EntitiesToInit"]
	var activeEIDs = state["ActiveEntities"]
	for module in modules:
		for eid in entitiesToInit:
			module.CopyVariablesEntity(state[eid])
	ExecuteScriptPhase("Init", entitiesToInit, moduleCallbackData)
	state["EntitiesToInit"] = []
	
	# 4. Action Phase
	for module in modules:
		module.ResetVariables(state, activeEIDs)
	ExecuteScriptPhase("Action", activeEIDs, moduleCallbackData)
	
	# 5. Physics Phase
	# :TODO:Panthavma:20220126:Optimize this by making the funcrefs beforehand
	for m in modules:
		funcref(m, "PhysicsPhaseStart").call_func(state, moduleCallbackData)
		for eid in activeEIDs:
			funcref(m, "PhysicsPhaseStartEntity").call_func(state[eid], moduleCallbackData)
	physicsModule.PhysicsPhase(state, previousState, activeEIDs)
	for m in modules:
		for eid in activeEIDs:
			funcref(m, "PhysicsPhaseEndEntity").call_func(state[eid], moduleCallbackData)
		funcref(m, "PhysicsPhaseEnd").call_func(state, moduleCallbackData)
	
	# 6. Transition Phase
	ExecuteScriptPhase("Transition", activeEIDs, moduleCallbackData)
	
	# 7. End the frame
	return state
	

func ExecuteScriptPhase(phaseName, eids, moduleCallbackData):
	# :TODO:Panthavma:20220126:Optimize this by making the funcrefs beforehand
	var state = moduleCallbackData["State"]
	moduleCallbackData["Phase"] = phaseName
	for m in modules:
		funcref(m, phaseName+"PhaseStart").call_func(state, moduleCallbackData)
		for eid in eids:
			funcref(m, phaseName+"PhaseStartEntity").call_func(state[eid], moduleCallbackData)
	for eid in eids:
		ExecuteCurrentFighterScript(eid, moduleCallbackData)
	for m in modules:
		for eid in eids:
			funcref(m, phaseName+"PhaseEndEntity").call_func(state[eid], moduleCallbackData)
		funcref(m, phaseName+"PhaseEnd").call_func(state, moduleCallbackData)


func ExecuteCurrentFighterScript(eid, moduleCallbackData):
	# 1. Get the fighter script / state from the entity (done outside maybe ?)
	var state = moduleCallbackData["State"]
	var fighterScript = GetCurrentFighterScriptOfEntity(eid, state)
	
	# 2. Execute each action one by one
	ExecuteFighterScript(fighterScript, eid, moduleCallbackData)

func GetCurrentFighterScriptOfEntity(eid, state):
	var fighterID = state[eid]["FighterID"]
	var stateName = state[eid]["State"]
	
	return GetFighterScript(fighterID, stateName)

func GetFighterScript(fighterID, stateName):
	if(fighterID >= fighterScripts.size()):
		Castagne.Error("GetFighterScript: Fighter ID " + str(fighterID) + " not found!")
		return null
	if(!fighterScripts[fighterID].has(stateName)):
		Castagne.Error("GetFighterScript: State "+str(stateName)+" on Fighter ID " + str(fighterID) + " not found!")
		return null
	
	return fighterScripts[fighterID][stateName]

func ExecuteFighterScript(fighterScript, eid, moduleCallbackData):
	var state = moduleCallbackData["State"]
	var entityState = state[eid]
	var phaseName = moduleCallbackData["Phase"]
	for action in fighterScript["Actions"]:
		ExecuteAction(action, phaseName, entityState, moduleCallbackData)

func ExecuteAction(action, phaseName, entityState, moduleCallbackData):
	if(phaseName in action["Flags"]):
		action["Func"].call_func(action["Args"], entityState, moduleCallbackData)



func UpdateGraphics(state):
	var moduleCallbackData = _BuildModuleCallbackData(state)
	for m in modules:
		m.UpdateGraphics(state, moduleCallbackData)





# ------------------------------------------------------------------------------
# Networking
var _onlineStart = false
var _onlineNbReady = 0

# :TODO:Panthavma:20220124:Make entity spawning work online

func _save_state() -> Dictionary:
	return _gameState

func _load_state(state: Dictionary) -> void:
	_gameState = state
	_lastGraphicsFrameUpdate = -1

func _network_process(_input: Dictionary) -> void:
	if(_onlineStart):
		var playerInputs = []
		for player in instancedData["Players"]:
			playerInputs.append(player["InputProvider"].onlineLastInput)
		_gameState = EngineTick(_gameState, playerInputs)


remotesync func _OnlineReady():
	if(!get_tree().is_network_server()):
		return
	_onlineNbReady += 1
	Castagne.Net.Log("Engine : Online Ready " + str(_onlineNbReady))
	if(_onlineNbReady == 2):
		#get_tree().paused = false
		Castagne.Net.Log("Engine : Online All Ready, starting...")
		Castagne.Net.StartSync()
#		rpc("_NetStartMatch")

#remotesync func _NetStartMatch():
#	get_tree().paused = false


func _on_SyncManager_sync_started() -> void:
	Castagne.Net.Log("Engine : SyncManager Sync Started")
	_onlineStart = true

func _OnlineInit():
	#SyncManager.connect("scene_spawned", self, "_on_SyncManager_scene_spawned")
	SyncManager.connect("sync_started", self, "_on_SyncManager_sync_started")
	#get_tree().paused = true
	set_network_master(1)
	Castagne.Net.StartLogging()
	
	Init(Castagne.battleInitData)
	
	rpc("_OnlineReady")



remotesync func OnlineEndMatch():
	Castagne.Net.StopSync()
	queue_free()


# ---------------------

# :TODO:Panthavma:20220124:Rework that a bit
func _BuildModuleCallbackData(currentState):
	var data = {
		"State": currentState,
		"InstancedData": instancedData,
		"Phase": "NotSpecified",
		"FighterScripts": fighterScripts,
		"Engine": self,
	}
	return data


func _ready():
	useOnline = Castagne.battleInitData["online"]
	if(useOnline):
		_OnlineInit()
	elif(initOnReady):
		Init(Castagne.battleInitData)

func _physics_process(_delta):
	# Physics process is fixed at 60 FPS
	if(!useOnline):
		var playerInputs = []
		for player in instancedData["Players"]:
			playerInputs.append(player["InputProvider"].PollRaw())
		_gameState = EngineTick(_gameState, playerInputs)

var _lastGraphicsFrameUpdate = -1
func _process(_delta):
	var trueFrameID = _gameState["TrueFrameID"]
	if(_lastGraphicsFrameUpdate < trueFrameID):
		_lastGraphicsFrameUpdate = trueFrameID
		UpdateGraphics(_gameState)


func Load(path):
	return load(path)