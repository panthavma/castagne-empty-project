extends Node


# :TODO:Panthavma:20220124:Allow only some modules to be called for slight perf boost ?


# Function callback signature:
# func FunctionName(args, eState, _data):

# --------------------------------------------------------------------------------------------------
# Callbacks and functions

# Used when the program starts, on loading.
func ModuleSetup():
	pass

# :TODO:Panthavma:20220124:Document the exact time it starts
# Used at the beginning of a battle
func BattleInit(_state, _data, _battleInitData):
	pass

# Called at the very beginning of each frame, before inputs
func FramePreStart(_state, _playerInputs, _data):
	pass
# Called at the beginning of each frame
func FrameStart(_state, _data):
	pass

# :TODO:Panthavma:20220124:Add per entity functions
# Init Phase: Prepares the entities themselves
func InitPhaseStart(_state, _data):
	pass
func InitPhaseStartEntity(_eState, _data):
	pass
func InitPhaseEndEntity(_eState, _data):
	pass
func InitPhaseEnd(_state, _data):
	pass

# Action Phase: Allows the characters to act
func ActionPhaseStart(_state, _data):
	pass
func ActionPhaseStartEntity(_eState, _data):
	pass
func ActionPhaseEndEntity(_eState, _data):
	pass
func ActionPhaseEnd(_state, _data):
	pass

# Physics Phase: Allows the characters to move, and computes the hits
func PhysicsPhaseStart(_state, _data):
	pass
func PhysicsPhaseStartEntity(_eState, _data):
	pass
func PhysicsPhaseEndEntity(_eState, _data):
	pass
func PhysicsPhaseEnd(_state, _data):
	pass
# :TODO:Panthavma:20220124:Allow a more flexible physics phase through modules

# Transition Phase: Allows the entities to change their state
func TransitionPhaseStart(_state, _data):
	pass
func TransitionPhaseStartEntity(_eState, _data):
	pass
func TransitionPhaseEndEntity(_eState, _data):
	pass
func TransitionPhaseEnd(_state, _data):
	pass

# Freeze Phase: Called when skipping frames
func FreezePhaseStart(_state, _data):
	pass
func FreezePhaseStartEntity(_eState, _data):
	pass
func FreezePhaseEndEntity(_eState, _data):
	pass
func FreezePhaseEnd(_state, _data):
	pass


# Called on each graphical frame to keep the display up to date
func UpdateGraphics(_state, _data):
	pass


# Confirms or infirms attacks
func IsAttackConfirmed(hitconfirm, _attackData, _hurtboxData, _aState, _dState, _state):
	return hitconfirm
func OnAttackConfirmed(_hitconfirm, _attackData, _hurtboxData, _aState, _dState, _state):
	pass








# --------------------------------------------------------------------------------------------------
# Helper functions

var moduleName = "Unnamed Module"
var moduleDocumentation = {"Description":""}

var moduleDocumentationCategories = {null:{"Name":"Uncategorized", "Description":"", "Variables":[], "Functions":[], "Flags":[], "Config":[], "BattleInitData":[]}}

func RegisterModule(_moduleName, _moduleDocumentation = null):
	moduleName = _moduleName
	if(_moduleDocumentation != null):
		moduleDocumentation = _moduleDocumentation


# Call before declaring functions or variables to group them in a category
func RegisterCategory(categoryName, categoryDocumentation = null):
	# TODO
	currentCategory = categoryName
	if(categoryDocumentation == null):
		categoryDocumentation = {
			"Description":"",
		}
	categoryDocumentation["Name"] = categoryName
	categoryDocumentation["Variables"] = []
	categoryDocumentation["Functions"] = []
	categoryDocumentation["Flags"] = []
	categoryDocumentation["Config"] = []
	categoryDocumentation["BattleInitData"] = []
	moduleDocumentationCategories[categoryName] = categoryDocumentation

# 
func RegisterVariableEntity(variableName, defaultValue, flags = null, documentation = null):
	variablesEntity[variableName] = _RegisterVariableCommon(variableName, defaultValue, flags, documentation, true)

func RegisterVariableGlobal(variableName, defaultValue, flags = null, documentation = null):
	variablesGlobal[variableName] = _RegisterVariableCommon(variableName, defaultValue, flags, documentation, false)

func _RegisterVariableCommon(variableName, defaultValue, flags, documentation, entityVariable):
	if(flags == null):
		flags = []
	
	if("ResetEachFrame" in flags):
		if(entityVariable):
			_variablesResetEntity[variableName] = defaultValue
		else:
			_variablesResetGlobal[variableName] = defaultValue
	
	# :TODO:Panthavma:20220203:Add a "temporary/volatile" flag for variables that won't get stored
	
	if(!"NoInit" in flags):
		if(entityVariable):
			_variablesInitEntity[variableName] = defaultValue
		else:
			_variablesInitGlobal[variableName] = defaultValue
	
	if(documentation == null):
		documentation = {
			"Description": ""
		}
	
	documentation["Name"] = variableName
	documentation["Default"] = defaultValue
	documentation["Flags"] = flags
	
	moduleDocumentationCategories[currentCategory]["Variables"].append(documentation)
	return documentation

# :TODO:Panthavma:20220124:Document the flags and how to document
# :TODO:Panthavma:20220124:Document how the functions are found
# Registers a function in the parser. 
func RegisterFunction(functionName, nbArguments, flags = null, documentation = null):
	var parseFunc = null
	var actionFunc = null
	var gizmoFunc = null
	
	if(flags == null):
		flags = []
	
	# :TODO:Panthavma:20220124:Look at making it parallel through the ThreadSafe flag
	# :TODO:Panthavma:20220124:Rework the flags
	
	if(flags.has("AllPhases")):
		flags += ["Init", "Action", "Transition"]
	
	if(!flags.has("Transition") and !flags.has("Action") and !flags.has("Init") and !flags.has("NoFunc")):
		flags += ["Init", "Action"]
	if(!flags.has("NoManual")):
		flags += ["Manual"]
	
	if(has_method("Parse"+functionName)):
		parseFunc = funcref(self, "Parse"+functionName)
	
	if(has_method(functionName)):
		actionFunc = funcref(self, functionName)
	
	if(has_method("Gizmo"+functionName)):
		gizmoFunc = funcref(self, "Gizmo"+functionName)
	
	if(parseFunc == null and actionFunc == null):
		Castagne.Error(functionName+" : Parse function or Action func couldn't be found.")
		return
	
	var docs = GetDefaultDocumentation(functionName, nbArguments, flags)
	if(documentation != null):
		Castagne.FuseDataOverwrite(docs, documentation)
	
	var argTypes = docs["Types"]
	if(argTypes == null):
		argTypes = []
	
	var maxArgs = 0
	for i in nbArguments:
		maxArgs = max(maxArgs, i)
	
	for i in range(maxArgs - argTypes.size()):
		argTypes += ["any"]
	docs["Types"] = argTypes
	
	var funcData = {
		"Name": functionName,
		"NbArgs": nbArguments,
		"ParseFunc": parseFunc,
		"ActionFunc": actionFunc,
		"GizmoFunc": gizmoFunc,
		"Flags": flags,
		"Documentation":docs,
		"Category":currentCategory,
		"Types":argTypes,
	}
	
	moduleDocumentationCategories[currentCategory]["Functions"].append(funcData)
	Castagne.functions[functionName] = funcData

# Registers a flag for the documentation
func RegisterFlag(flagName, documentation = null):
	if(documentation == null):
		documentation = {
			"Description": ""
		}
	documentation["Name"] = flagName
	moduleDocumentationCategories[currentCategory]["Flags"].append(documentation)

# Registers a configuration option
func RegisterConfig(keyName, defaultValue, documentation=null):
	var docs = {
		"Description": "",
		"Flags":[],
		"Name":keyName,
	}
	if(documentation != null):
		Castagne.FuseDataOverwrite(docs, documentation)
	docs["Key"]=keyName
	docs["Default"]=defaultValue
	moduleDocumentationCategories[currentCategory]["Config"].append(docs)
	
	configDefault[keyName] = defaultValue

# Register a battle init data value, used by castagne at initialization.
func RegisterBattleInitData(keyName, defaultValue, documentation=null):
	if(documentation == null):
		documentation = {
			"Description": ""
		}
	documentation["Name"]=keyName
	moduleDocumentationCategories[currentCategory]["BattleInitData"].append(documentation)
	
	battleInitDataDefault[keyName] = defaultValue


# :TODO:Panthavma:20220420:Make them actual flags instead of strings, with a more global system
func HasFlag(eState, flagName):
	if(eState.has("Flags")):
		return eState["Flags"].has(flagName)
	return false
func SetFlag(eState, flagName, flagVarName = "Flags"):
	if(!eState[flagVarName].has(flagName)):
		eState[flagVarName] += [flagName]
func UnsetFlag(eState, flagName, flagVarName = "Flags"):
	eState[flagVarName].erase(flagName)

func CallFunction(functionName, args, eState, data):
	Castagne.functions[functionName]["ActionFunc"].call_func(args, eState, data)

func ModuleLog(text, eState = null):
	var eidName = ("Entity ["+str(eState["EID"])+"]" if eState != null else "")
	Castagne.Log("Module "+moduleName+" Log "+eidName+" : " + text)
func ModuleError(text, eState = null):
	var eidName = ("Entity ["+str(eState["EID"])+"]" if eState != null else "")
	Castagne.Error("Module "+moduleName+" Error "+eidName+" : " + text)

func ArgStr(args, eState, argID, default = null):
	if(args.size() <= argID):
		if(default == null):
			Castagne.Error("ArgStr ("+argID+"): This argument needs a default but doesn't have one")
		return default
	var value = args[argID]
	if(eState == null):
		return default
	if(eState.has(value)):
		return str(eState[value])
	return value

func ArgVar(args, eState, argID, default = null):
	if(args.size() <= argID):
		if(default == null):
			Castagne.Error("ArgVar ("+argID+"): This argument needs a default but doesn't have one")
		return default
	return args[argID]

func ArgInt(args, eState, argID, default = null):
	if(args.size() <= argID):
		if(default == null):
			Castagne.Error("ArgInt ("+str(argID)+"): This argument needs a default but doesn't have one")
			return 1
		return default
	var value = str(args[argID])
	if(value.is_valid_integer()):
		return int(value)
	if(eState == null):
		return default
	if(eState.has(value)):
		var v = eState[value]
		return int(v)
	# :TODO:Panthavma:20220126:Make the message more precise
	Castagne.Error("ArgInt ("+str(argID)+"): Couldn't find variable " + value)
	if(default == null):
		return 1
	return default


# :TODO:Panthavma:20220203:Replace by True/False constants
func ArgBool(args, eState, argID, default = null):
	if(args.size() <= argID):
		if(default == null):
			Castagne.Error("ArgBool ("+argID+"): This argument needs a default but doesn't have one")
		return default
	var value = str(args[argID])
	if(value.is_valid_integer()):
		return int(value) > 0
	if(eState.has(value)):
		return int(eState[value]) > 0
	# :TODO:Panthavma:20220126:Make the message more precise
	Castagne.Error("ArgBool ("+argID+"): Couldn't find variable " + value)
	return default






# --------------------------------------------------------------------------------------------------
# Internals
var engine
var currentCategory = null
var variablesGlobal = {}
var variablesEntity = {}
var _variablesInitGlobal = {}
var _variablesInitEntity = {}
var _variablesResetGlobal = {}
var _variablesResetEntity = {}
var configDefault = {}
var battleInitDataDefault = {}

func ArgRaw(args, argID, default = null):
	if(args.size() <= argID):
		if(default == null):
			Castagne.Error("ArgRaw ("+argID+"): This argument needs a default but doesn't have one")
		return default
	return args[argID]





func GetDefaultDocumentation(functionName, nbArguments, _flags):
	var d = {
		"Name":functionName,
		"NbArgs": nbArguments,
		"ArgsDesc":[],
		"Description":"Unspecified.",
		"Arguments":[],
		"Types":null,
	}
	
	for _i in range(nbArguments.size()):
		d["ArgsDesc"].append("Unspecified.")
	
	return d

func CopyVariablesGlobal(state):
	Castagne.FuseDataOverwrite(state, _variablesInitGlobal.duplicate(true))

func CopyVariablesEntity(eState):
	Castagne.FuseDataNoOverwrite(eState, _variablesInitEntity.duplicate(true))

func ResetVariables(state, activeEIDs):
	Castagne.FuseDataOverwrite(state, _variablesResetGlobal.duplicate(true))
	for eid in activeEIDs:
		Castagne.FuseDataOverwrite(state[eid], _variablesResetEntity.duplicate(true))
