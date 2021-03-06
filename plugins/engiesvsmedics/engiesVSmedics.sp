#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <clients>
#include <morecolors>

// Doublejump add-on starts
ConVar g_cvJumpMax = null;
ConVar g_cvAllorTeam = null;
ConVar g_cvJumpBoost = null;
ConVar g_cvJumpEnable = null;
ConVar g_cvBlueorRed = null;
float g_flBoost = 250.0;
bool g_bDoubleJump;
bool g_bAllorTeam;
bool g_bBlueorRed;
int g_iJumpMax;
int g_iLastButtons[MAXPLAYERS+1];
int g_iLastFlags[MAXPLAYERS+1];
int g_iJumps[MAXPLAYERS+1];
// Doublejump add-on ends

int DiedYet[64]; //this array stores wether a player is in the game and wether a player is in blue or red team
int GameStarted=0; //this int stores the amount of time the game has been started, resets when the game ends.
bool IsSettingTeam = false; //this bool switches to false when balancing teams so that the player death trackers doesn't messes up
bool ZombieStarted = false; //This variable is set to true after some time after round start to prevent victory from triggering too soon
ConVar zve_setup_time = null;
ConVar zve_round_time = null;
ConVar zve_tanks = null;
ConVar zve_super_zombies = null;
bool WaitingEnded = false;
Handle RedWonHandle = INVALID_HANDLE;
Handle SuperZombiesTimerHandle = INVALID_HANDLE;
int CountDownCounter = 0;
bool SuperZombies = false;
/* HOW THIS PLUGIN WORKS:
 *	Basically, it keeps track of wether a player has died or not during a game (in the DiedYet array)
 *	when a player is connected it has its DiedYet value set to -1 if the game has started, 1 else.
 *	when a player dies, it has its DiedYet value set to -1 too.
 *  if a player has its DiedYet value set to -1, it will spawn as a blue medic
 *      if a player has its DiedYet value set to 1, it will spawn as a red engineer.
 *	Any sentry will instantly be destroyed and blue medics can only use melee weapons.
 */

public Plugin myinfo ={
	name = "Engineers Vs Zombies",
	author = "shewowkees",
	description = "zombie like gamemode",
	version = "1.2",
	url = "noSiteYet"
};

public void OnPluginStart (){
	PrintToServer("Engies vs Medics V1.2 by shewowkees, inspired by Muselk.");
	HookEvent("player_spawn",Evt_PlayerSpawnChangeClass,EventHookMode_Post);
	HookEvent("player_spawn",Evt_PlayerSpawnChangeTeam,EventHookMode_Pre);
	HookEvent("player_death",Evt_PlayerDeath,EventHookMode_Post);
	HookEvent("tf_game_over",Evt_TFGameOver,EventHookMode_Post);
	HookEvent("teamplay_round_start", Evt_RoundStart);
	HookEvent("teamplay_waiting_begins",Evt_WaitingBegins,EventHookMode_Post);
	HookEvent("teamplay_round_win",Evt_RoundEnd);
	HookEvent("player_disconnect",Evt_PlayerDisconnect,EventHookMode_Post);
	HookEvent("player_hurt",Evt_PlayerHurt, EventHookMode_Pre);
	AddCommandListener(CommandListener_Build, "build");
	AddCommandListener(CommandListener_ChangeClass, "joinclass");
	AddCommandListener(CommandListener_ChangeTeam, "jointeam");
	AddCommandListener(CommandListener_Spectate, "spectate");
	//CONVARS

	zve_round_time = CreateConVar("zve_round_time", "314", "Round time, 5 minutes by default.");
	zve_setup_time = CreateConVar("zve_setup_time", "45.0", "Setup time, 30s by default.");
	zve_super_zombies = CreateConVar("zve_super_zombies", "30.0", "How much time before round end zombies gain super abilities. Set to 0 to disable it.")
	zve_tanks = CreateConVar("zve_tanks", "60.0", "How much time after setup the first zombies have a health boost. Set to 0 to disable it.")
	AutoExecConfig(true, "plugin_zve");
	RegAdminCmd("sm_forcepickzombie", Zve_ForcePickZombie, ADMFLAG_GENERIC, "Forces to randomly pick a player from red and forces them to join blue.");
	RegAdminCmd("sm_fpz", Zve_ForcePickZombie, ADMFLAG_GENERIC, "Forces to randomly pick a player from red and forces them to join blue.");
	LoadTranslations("engiesVSmedics.phrases");
	LoadTranslations("common.phrases");
	
	// Double Jump
	g_cvJumpEnable = CreateConVar("sm_doublejump_enabled", "1", "Enables double jumping");
	g_cvJumpBoost = CreateConVar("sm_doublejump_boost", "250.0", "Vertical boost count");
	g_cvJumpMax = CreateConVar("sm_doublejump_max", "1", "Maximum numbers of double jumps");
	g_cvAllorTeam = CreateConVar("sm_doublejump_allorteam", "1", "Specifies whether you want doublejump only enabled on one team or on all teams");
	g_cvBlueorRed = CreateConVar("sm_doublejump_redorblue", "0", "Specifies which team to pick. Red = 1, Blue = 0");
	
	g_cvJumpEnable.AddChangeHook(convar_ChangeEnable);
	g_cvJumpBoost.AddChangeHook(convar_ChangeBoost);
	g_cvJumpMax.AddChangeHook(convar_ChangeMax);
	g_cvAllorTeam.AddChangeHook(convar_AllorTeam);
	g_cvBlueorRed.AddChangeHook(convar_BlueorRed);

	g_bBlueorRed = g_cvBlueorRed.BoolValue;
	g_bAllorTeam = g_cvAllorTeam.BoolValue;
	g_bDoubleJump = g_cvJumpEnable.BoolValue;
	g_flBoost = g_cvJumpBoost.FloatValue;
	g_iJumpMax = g_cvJumpMax.IntValue;
}
/*
 * This method disables respawn times and prevents teams auto balance.
 * It also makes the server ban the idle players immediatly, only switching
 *	them to spectator mode would cause the plugin to misbehave.
 *
 */
public OnMapStart(){
	function_ResetPlugin();
	ServerCommand("mp_disable_respawn_times 1");
	ServerCommand("mp_teams_unbalance_limit 30");
	ServerCommand("mp_idledealmethod 2");
	ServerCommand("mp_autoteambalance 0");
	ServerCommand("mp_idlemaxtime 10");
	ServerCommand("mp_waitingforplayers_time 35");
	ServerCommand("mp_scrambleteams_auto 0");
	ServerCommand("tf_weapon_criticals_melee 0");
	ServerCommand("sm_cvar tf_dropped_weapon_lifetime 0");
	//ServerCommand("sm_cvar sv_lowedict_action 5");
	WaitingEnded = false;


}
// public OnEventShutdown()
// {
// UnHookEvent("player_spawn",Evt_PlayerSpawnChangeClass);
// UnHookEvent("player_spawn",Evt_PlayerSpawnChangeTeam);
// UnHookEvent("player_death",Evt_PlayerDeath);
// UnHookEvent("tf_game_over",Evt_TFGameOver);
// UnHookEvent("player_regenerate",Evt_PlayerRegenerate);
// UnHookEvent("teamplay_round_start", Evt_RoundStart);
// UnHookEvent("teamplay_waiting_begins",Evt_WaitingBegins);
// UnHookEvent("player_disconnect",Evt_PlayerDisconnect);
// }
/*
 * This method initializes DiedYet of the connecting client to the right value.
 */
public void OnClientPostAdminCheck(int client){
	if(function_countPlayers()==0){

		function_ResetPlugin();

	}
	if(ZombieStarted) {
		DiedYet[client]=-1;
	}else{
		DiedYet[client]=1;
	}


}



public void TF2_OnWaitingForPlayersEnd(){

	WaitingEnded = true;

}


//EVENTS




//PLAYER RELATED EVENTS

/*
 * This code is from Tsunami's TF2 build restrictions. It prevents engineers
 * from even placing a sentry.
 *
 */
public Action CommandListener_Build(client, const String:command[], argc)
{

	// Get arguments
	decl String:sObjectType[256]
	GetCmdArg(1, sObjectType, sizeof(sObjectType));

	// Get object mode, type and client's team
	new iObjectType = StringToInt(sObjectType),
	iTeam       = GetClientTeam(client);

	// If invalid object type passed, or client is not on Blu or Red
	if(iObjectType < view_as<int>(TFObject_Dispenser) || iObjectType > view_as<int>(TFObject_Sentry) || iTeam < view_as<int>(TFTeam_Red) ) {

		return Plugin_Continue;
	}

	//Blocks sentry building
	else if(iObjectType==view_as<int>(TFObject_Sentry) ) {
		CPrintToChat(client, "\x05[EVZ]:\x01 %t", "sentry_restric");
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action CommandListener_ChangeTeam(client, const String:command[],argc){
	decl String:arg1[256]
	GetCmdArg(1, arg1, sizeof(arg1));
	if(strcmp(arg1,"blue",false)==0 && DiedYet[client] == -1) {

		return Plugin_Continue;

	}else if(DiedYet[client]==-1) {

		ClientCommand(client,"jointeam blue");

	}
	if(strcmp(arg1,"red",false)==0 && DiedYet[client]== 1) {

		return Plugin_Continue;

	}else if(DiedYet[client]==1) {

		ClientCommand(client,"jointeam red");

	}
	CPrintToChat(client, "\x05[EVZ]:\x01 %t", "betray_team");
	return Plugin_Handled;
	// decl String:arg1[256]
	// GetCmdArgString(arg1, sizeof(arg1));
	// CPrintToChatAll(arg1);
	// return Plugin_Continue;

}

public Action CommandListener_ChangeClass(client,const String:command[], argc){
	decl String:arg1[256]
	GetCmdArg(1, arg1, sizeof(arg1));
	if(strcmp(arg1,"medic",false)==0 && DiedYet[client] == -1) {

		return Plugin_Continue;

	}else if(DiedYet[client]==-1) {

		ClientCommand(client,"joinclass medic");

	}
	if(strcmp(arg1,"engineer",false)==0 && DiedYet[client]== 1) {

		return Plugin_Continue;

	}else if(DiedYet[client]==1) {

		ClientCommand(client,"joinclass engineer");

	}
	CPrintToChat(client, "\x05[EVZ]:\x01 %t", "change_class");
	return Plugin_Handled;
	// decl String:arg1[256]
	// GetCmdArgString(arg1, sizeof(arg1));
	// CPrintToChatAll(arg1);
	// return Plugin_Continue;
}


public Action CommandListener_Spectate(client, const String:command[], argc){
	CPrintToChat(client, "\x05[EVZ]:\x01 %t", "change_spectator");
	return Plugin_Handled;
}

/*
 * This method forces the spawning player to switch to the right team BEFORE he appears
 */
public Action Evt_PlayerSpawnChangeTeam(Event event, const char[] name, bool dontBroadcast){

	int client = GetClientOfUserId(event .GetInt("userid"));
	if(DiedYet[client]==-1 && TF2_GetClientTeam(client)==TFTeam_Red) { //if client is supposed to be a blue medic
		function_SafeTeamChange(client,TFTeam_Blue);
		TF2_RespawnPlayer(client);

	}else if(DiedYet[client]==1) { //if the client is supposed to be a red engineer.

		if( TF2_GetClientTeam(client)==TFTeam_Blue ) {
			DiedYet[client]=-1;
		}

	}
}
/*
 * This method forces the player to be on the right team, the right class and to use the right weapons.
 */
public Action Evt_RoundEnd(Event event, const char[] name, bool dontBroadcast) 
{
	ServerCommand("sm_outline @all 0");
}
public Action Evt_PlayerSpawnChangeClass(Event event, const char[] name, bool dontBroadcast){

	int client = GetClientOfUserId(event .GetInt("userid"));
	if(DiedYet[client]==0) {

		if(GameStarted>0) {
			DiedYet[client]=-1;
		}else{
			DiedYet[client]=1;
		}

	}
	if(DiedYet[client]==-1 || DiedYet[client]==0) { //if client is supposed to be a blue medic


		if( TF2_GetPlayerClass(client) != TFClass_Medic) { //if he isn't a medic, changes his class,  him and makes him respawn.
			CPrintToChat(client, "\x05[EVZ]:\x01 %t", "only_medic");
			TF2_SetPlayerClass(client, TFClass_Medic, true, true);
			TF2_RegeneratePlayer(client);
		}


		function_StripToMelee(client);
		function_MakeSuperZombie(client);

	}else if(DiedYet[client]==1) { //if the client is supposed to be a red engineer.


		if( TF2_GetPlayerClass(client) != TFClass_Engineer) {        //if the client isn't an engineer, changes his class, kills him and makes him respawn
			CPrintToChat(client, "\x05[EVZ]:\x01 %t", "only_engineer");
			TF2_SetPlayerClass(client, TFClass_Engineer, true, true);
			DiedYet[client]=1;         //sets the diedyet value to 1 because the suicide would set it to -1
			TF2_RegeneratePlayer(client);
		}


	}
	function_CheckVictory();
}

public Action Evt_PlayerHurt(Event event, const char[] name, bool dontBroadcast){

	int client = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if(DiedYet[attacker]==-1){

		if(IsValidEntity(client) && IsClientInGame(client)&& WaitingEnded && ZombieStarted && !IsSettingTeam) {

			int EntProp = GetEntProp(client, Prop_Send, "m_lifeState");
			SetEntProp(client, Prop_Send, "m_lifeState", 2);
			ChangeClientTeam(client, view_as<int>(TFTeam_Blue) );
			TF2_SetPlayerClass(client, TFClass_Medic, true, true);
			SetEntProp(client, Prop_Send, "m_lifeState", EntProp);
			TF2_RegeneratePlayer(client);
			function_StripToMelee(client);
			DiedYet[client]=-1;
			function_CheckVictory();


		}

	}

}
/*
 * This method updates the DiedValue of a player if needed,changes his team and checks for victory
 */
public Action Evt_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{ //On player death, sets his DiedYet value to -1
	if(WaitingEnded && ZombieStarted && !IsSettingTeam) 
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		if(GameStarted>0) 
		{
			CPrintToChat(client, "\x05[EVZ]:\x01 %t", "infected");
			DiedYet[client] = -1;
			TF2_ChangeClientTeam(client,TFTeam_Blue);
			TF2_SetPlayerClass(client, TFClass_Medic, true, true);

		}
		function_CheckVictory();
	}
	new count, client;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Red)
		{
			client = i;
			count++;
		}
	}
	if (count == 2)
	{
		TF2_AddCondition(client, view_as<TFCond>(19), TFCondDuration_Infinite, 0);
	}
	if (count == 1)
    {
        TF2_AddCondition(client, view_as<TFCond>(42), TFCondDuration_Infinite, 0);
        TF2_AddCondition(client, view_as<TFCond>(49), TFCondDuration_Infinite, 0);
    }
}



/*
 * This method resets a player's DiedYet value when he disconnects.
 */
public Action Evt_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast){

	int client = GetClientOfUserId(event .GetInt("userid"));
	DiedYet[client] = 0;
	function_CheckVictory();




}


//ROUND RELATED EVENTS


/*
 * This functions decrements GameStarted because it will be incremented when the waiting begins
 */
public Action Evt_WaitingBegins(Event event, const char[] name, bool dontBroadcast){
	GameStarted=-1;
}
/*
 * This method deletes all unwanted elements from the map and balances the teams
 */
public Action Evt_RoundStart(Event event, const char[] name, bool dontBroadcast){
	SuperZombies = false;
	ServerCommand("sm_doublejump_boost 250");
	ServerCommand("sv_gravity 800");
	if(RedWonHandle!=INVALID_HANDLE) {
		KillTimer(RedWonHandle,false);
		RedWonHandle=INVALID_HANDLE;
	}
	if(SuperZombiesTimerHandle!=INVALID_HANDLE) {
		KillTimer(SuperZombiesTimerHandle,false);
		SuperZombiesTimerHandle=INVALID_HANDLE;
	}
	float ActualRoundTime = GetConVarFloat(zve_round_time)+GetConVarFloat(zve_setup_time);
	RedWonHandle = CreateTimer(ActualRoundTime,RedWon);
	if(GetConVarFloat(zve_super_zombies)>0.0) {
		SuperZombiesTimerHandle = CreateTimer(ActualRoundTime-GetConVarFloat(zve_super_zombies), SuperZombiesTimer);
	}

	function_PrepareMap();
	if(WaitingEnded) {
		function_AllEngineers(false);
	}

	CreateTimer(2.30,Stun);
	GameStarted++;
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "version");
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "red_goal");
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "blue_goal");
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "source_plugin");
	//PrintToServer("GameStarted incremented");//Debugging instruction
	new count, client;
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && TF2_GetClientTeam(i) == TFTeam_Red)
		{
			client = i;
			count++;
		}
	}
	if (count == 2)
	{
		TF2_AddCondition(client, view_as<TFCond>(31), TFCondDuration_Infinite, 0);
		ServerCommand("sm_outline \"#%N\" 1", client);
	}
	if (count == 1)
    {
        TF2_AddCondition(client, view_as<TFCond>(42), TFCondDuration_Infinite, 0);
        TF2_AddCondition(client, view_as<TFCond>(49), TFCondDuration_Infinite, 0);
    }
}

public Action Evt_TFGameOver(Event event, const char[] name, bool dontBroadcast){ //Once the game is over, resets the DiedYet values

	GameStarted = 0;


}


//TIMERS
public Action SuperZombiesTimer(Handle timer){
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "power_up");
	SuperZombies = true;
	ServerCommand("sv_gravity 400");
	ServerCommand("sm_doublejump_boost 350")
	for(int i=0; i<64; i++) {
		if(DiedYet[i]==-1) {

			function_MakeSuperZombie(i);

		}
	}
	SuperZombiesTimerHandle = INVALID_HANDLE;


}

public Action Stun(Handle timer){
	function_StunTeam(TFTeam_Blue);
	if(WaitingEnded) {
		float setupTime = GetConVarFloat(zve_setup_time);
		CreateTimer(setupTime, Infection);
		if(setupTime>11.0) {
			CreateTimer(setupTime-11.0, CountDownStart);
		}
	}


}
public Action CountDownStart(Handle timer){

	CreateTimer(1.0, CountDown, _, TIMER_REPEAT);
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "infection_start");

}
public Action CountDown(Handle timer){
	if(CountDownCounter<10) {
		char message[] = "\x05[EVZ]:\x01 ";
		char timeLeft[3];
		IntToString(10-CountDownCounter, timeLeft, 3);
		StrCat(message, sizeof(message)+3,timeLeft);
		CPrintToChatAll(message);
		CountDownCounter++;
		return Plugin_Continue;
	}else{
		CountDownCounter = 0;
		KillTimer(timer, false);
		return Plugin_Stop;

	}


}

public Action Infection(Handle timer){
	CPrintToChatAll("\x05[EVZ]:\x01 %t", "infection_unleashed");


	function_ResetTeams(true);
	ZombieStarted = true;
}
public Action RedWon(Handle timer){

	function_teamWin(TFTeam_Red);
	RedWonHandle=INVALID_HANDLE;

}


//FUNCTIONS



/*
 * This function deletes all element that can influence game winning from the map.
 * The game winngin elements part is from perky (hide n seek plugin).
 *
 * @param -
 * @return -
 */
public function_PrepareMap(){

	//code below is from Perky in Hide n seek plugin, it disables cp and ctf gamemodes.
	//following code disables cp and pl

	/*SetVariantInt(0);
	function_sendEntitiesInput("trigger_capture_area","SetTeam");
	function_sendEntitiesInput("trigger_capture_area","Disable");
	function_sendEntitiesInput("item_teamflag","Disable");
	SetVariantInt(0);

	function_sendEntitiesInput("team_round_timer","SetSetupTime");
	SetVariantInt(GetConVarInt(zve_round_time)+GetConVarInt(zve_setup_time));
	function_sendEntitiesInput("team_round_timer","SetTime");*/
	SetVariantInt(0);
	function_sendEntitiesInput("trigger_capture_area","SetTeam");
	function_sendEntitiesInput("trigger_capture_area","Disable");
	function_sendEntitiesInput("item_teamflag","Disable");
	SetVariantInt(0);
	/*if(FindEntityByClassname(-1,"dispenser_touch_trigger")){ //NOT STABLE YET
		function_sendEntitiesInput("team_round_timer","SetTime");
		function_sendEntitiesInput("team_round_timer","SetSetupTime");
		SetVariantInt(-1);
		function_sendEntitiesInput("team_round_timer","AddTime");
	}

	function_sendEntitiesInput("team_round_timer","SetSetupTime");
	SetVariantInt(GetConVarInt(zve_round_time)+GetConVarInt(zve_setup_time));
	function_sendEntitiesInput("team_round_timer","SetTime");*/
	function_DeleteDoors();

}
/*
 * This function deletes door and spawnroom things
 */
public function_DeleteDoors(){ //following code opens all doors. This part was made by myself

	function_deleteEntities("func_door",true);
	function_deleteEntities("func_door_rotating",true);
	function_deleteEntities("func_respawnroomvisualizer",false);
	function_sendEntitiesInput("trigger_teleport","Enable");

}
/*
 * This functions makes a team given in argument win.
 * The code is from perky, author of the hide n seek plugin
 *
 * @param team		The TFTeam that will win.
 * @return -
 */
public void function_teamWin(TFTeam team) //code from hide n seek
{
	//this code kills the timer that makes redteam win

	//this is the code that actually makes a team win
	int edict_index = FindEntityByClassname(-1, "team_control_point_master");
	if (edict_index == -1)
	{
		int g_ctf = CreateEntityByName("team_control_point_master");
		DispatchSpawn(g_ctf);
		AcceptEntityInput(g_ctf, "Enable");
	}

	int search = FindEntityByClassname(-1, "team_control_point_master")
	SetVariantInt(view_as<int>(team) );
	AcceptEntityInput(search, "SetWinner");

	//AcceptEntityInput(search, "SetTeam");
	//AcceptEntityInput(search, "RoundWin");
	//AcceptEntityInput(search, "kill");





}
/*
 * This function computes the teams balance depending on the player counts and
 * puts them in the right team and if kills is true, it kills all the players.
 *
 * @param kills		Wether the function should kill the players or not.
 * @return -
 *
 *
 */



public void function_ResetTeams(bool kills){

	IsSettingTeam=true;
	//following code counts the connected players
	int PlayerCount=0;
	for(int i=0; i<64; i++) {

		if(DiedYet[i]!=0) {

			PlayerCount++;

		}

	}

	//following code will compute the needed starting blue Medics, depending on the player count.
	int StartingMedics = 0;
	if(PlayerCount > 1) { //if there is 2 or more players

		StartingMedics=1;

	}
	if(PlayerCount>5) {

		StartingMedics=2;

	}
	if(PlayerCount >10) {

		StartingMedics=3;

	}
	if(PlayerCount >18) {

		StartingMedics=4;

	}

	//following code will make needed players start as medic
	while(StartingMedics>0) {
		int i = GetRandomInt(0,63);
		if(DiedYet[i]==1) {
			DiedYet[i]=-1;
			StartingMedics--;

		}
	}
	//Kills all the players
	if(kills) 
	{

		for(int i=0; i<64; i++) 
		{

			if(DiedYet[i]==-1) 
			{

				if(IsClientInGame(i)) 
				{
					int EntProp = GetEntProp(i, Prop_Send, "m_lifeState");
					SetEntProp(i, Prop_Send, "m_lifeState", 2);
					ChangeClientTeam(i, view_as<int>(TFTeam_Blue) );
					TF2_SetPlayerClass(i, TFClass_Medic, true, true);
					SetEntProp(i, Prop_Send, "m_lifeState", EntProp);
					TF2_RegeneratePlayer(i);
					function_StripToMelee(i);
					DiedYet[i]=-1;
					function_CheckVictory();

				}

			}

		}

	}

	IsSettingTeam=false;


}
/*
 * This function checks if victory conditions for blue team are met and
 * triggers the victory and resets teams if needed.
 *
 * @param -
 * @return -
 *
 *
 */
public void function_CheckVictory(){

	if(ZombieStarted==false) {
		return;
	}

	bool AllEngineersDead = true;
	bool AllMedicsDead = true;
	for(int i=0; i<64; i++) {
		if(DiedYet[i]==1) {

			AllEngineersDead=false;

		}
		if(DiedYet[i]==-1){

			AllMedicsDead=false;

		}

	}
	if(AllEngineersDead) {

		function_teamWin(TFTeam_Blue);
		ZombieStarted=false;

	}else if(AllMedicsDead && ZombieStarted){

		function_teamWin(TFTeam_Red);
		ZombieStarted=false;
	}

}

/*
 * This function puts all players to red engineers.
 *
 * @param kill          if true, will kill the players and force their respawn.
 * @return -
 *
 *
 */
public void function_AllEngineers(bool kill)
{
	for(int i=0; i<64; i++) 
	{
		if(DiedYet[i]!=0) 
		{
			DiedYet[i]=1;
			function_SafeTeamChange(i,TFTeam_Red);
			TF2_RespawnPlayer(i);
			if(kill==true) 
			{
				ForcePlayerSuicide(i);
				TF2_RegeneratePlayer(i);
			}

		}

	}

}
/* This function stuns all the players of a given team
 *
 */

public void function_StunTeam(TFTeam team){
	float time = GetConVarFloat(zve_setup_time);
	if(time>30.0) 
	{
		time=30.0
	}
	int cmp=-10;
	if(team==TFTeam_Blue) 
	{
		cmp=-1;
	}
	else if(team==TFTeam_Red) 
	{
		cmp=1;
	}

	for(int i=0; i<64; i++) 
	{

		if(DiedYet[i]==cmp) 
		{
			TF2_StunPlayer(i, time, 0.0, TF_STUNFLAG_BONKSTUCK, 0);
			TF2_AddCondition(i,view_as<TFCond>(55), GetConVarFloat(zve_setup_time)+GetConVarFloat(zve_tanks), 0);
		}

	}
}
/*
 * This function resets every global scope variable
 */
public void function_ResetPlugin(){
	int EmptyDiedYet[64];
	DiedYet = EmptyDiedYet;
	GameStarted=0;   //this int stores the amount of time the game has been started, resets when the game ends.
	IsSettingTeam = false;   //this bool switches to false when balancing teams so that the player death trackers doesn't messes up
	ZombieStarted = false;
}

public void function_StripToMelee(int client){

	TF2_AddCondition(client, view_as<TFCond>(85), TFCondDuration_Infinite, 0);
	TF2_AddCondition(client, view_as<TFCond>(41), TFCondDuration_Infinite, 0);
	TF2_RemoveCondition(client, view_as<TFCond>(85) );
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Primary);
	TF2_RemoveWeaponSlot(client, TFWeaponSlot_Secondary);

}

public void function_MakeSuperZombie(int client){

	if(SuperZombies) {
		TF2_AddCondition(client, view_as<TFCond>(38), TFCondDuration_Infinite, 0);
	}


}

public void function_SafeTeamChange(int client, TFTeam team){

	if(IsValidEntity(client) && IsClientInGame(client)) {

		int EntProp = GetEntProp(client, Prop_Send, "m_lifeState");
		SetEntProp(client, Prop_Send, "m_lifeState", 2);
		ChangeClientTeam(client, view_as<int>(team) );
		SetEntProp(client, Prop_Send, "m_lifeState", EntProp);


	}
}

public void function_sendEntitiesInput(const char[] entityname, const char[] input){

	int x = -1
	int EntIndex;
	bool HasFound = true;

	while(HasFound) {

		EntIndex = FindEntityByClassname (x, entityname); //finds doors

		if(EntIndex==-1) {//breaks the loop if no matching entity has been found

			HasFound=false;

		}else{

			if (IsValidEntity(EntIndex)) {

				AcceptEntityInput(EntIndex, input); //Deletes the door it.
				x = EntIndex;
			}
		}
	}
}

public void function_deleteEntities(const char[] entityname, bool isDoor){

	if(isDoor){
		function_sendEntitiesInput(entityname, "Open");
	}
	function_sendEntitiesInput(entityname,"Kill");

}

public int function_countPlayers(){
	int count=0;
	for(int i=0;i<64;i++){

		if(DiedYet[i]!=0){
			count++;
		}

	}
	return count;
}

// COMMANDS
public Action Zve_ForcePickZombie(int client, int args)
{
	new chosenzombie = GetRandomPlayer(3);
	
	if (chosenzombie == 2)
	{
		CPrintToChat(client, "\x05[EVZ]:\x01 %t", "forcepickzombiefail");
		return Plugin_Handled;
		}
	CPrintToChatAll("\x05[ZVE]:\x01 %t", chosenzombie);
	function_SafeTeamChange(chosenzombie, TFTeam_Blue);
	return Plugin_Handled
}

stock IsValidClient(client, bool replaycheck = true)
{
	if(client <= 0 || client > MaxClients || !IsClientInGame(client) || GetEntProp(client, Prop_Send, "m_bIsCoaching"))
	{
		return false;
	}
	if(replaycheck)
	{
		if(IsClientSourceTV(client) || IsClientReplay(client))
		{
			return false;
		}
	}
	return true;
}

stock GetRandomPlayer(team) { 
    new clients[MaxClients + 1], clientCount; 
     
    for (new i = 1; i <= MaxClients; i++) 
        if (IsClientInGame(i) && GetClientTeam(i) == team) 
            clients[clientCount++] = i; 
     
    if (clientCount < 2) 
        return -1; 
     
    return clients[GetRandomInt(0, clientCount - 1)]; 
}  

/*Team List
3 - Red / T
2 - Blue / CT
1 - Spectator
0 - No Team
*/

// Double jump add-on

public int convar_ChangeBoost(Handle convar, const char[] oldVal, const char[] newVal)
{
	g_flBoost = StringToFloat(newVal);
}

public int convar_ChangeEnable(Handle convar, const char[] oldVal, const char[] newVal)
{
	if(StringToInt(newVal) >=1)
	{
		g_bDoubleJump = true;
	}
	else
	{
		g_bDoubleJump = false;
	}
}

public void convar_ChangeMax(Handle convar, const char[] oldVal, const char[] newVal)
{
	g_iJumpMax = StringToInt(newVal);
}

public void convar_AllorTeam(Handle convar, const char[] oldVal, const char[] newVal)
{
	if(StringToInt(newVal) >=1)
	{
		g_bAllorTeam = true;
	}
	else
	{
		g_bDoubleJump = false;
	}
}

public void convar_BlueorRed(Handle convar, const char[] oldVal, const char[] newVal)
{
	if(StringToInt(newVal) >=0)
	{
		g_bBlueorRed = true;
	}
	else
	{
		g_bBlueorRed = false;
	}
}

public void OnGrameFrame()
{
	if(g_bDoubleJump)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if(!g_bAllorTeam)
			{
				if(IsClientInGame(i) && IsPlayerAlive(i))
				{
					DoubleJump(i);
				}
			}
			else if(g_bAllorTeam)
			{
				if(!g_bBlueorRed)
				{
					if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 3)
					{
						DoubleJump(i);
					}
				}
				else if(g_bBlueorRed)
				{
					if(IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == 2)
					{
						DoubleJump(i);
					}
				}
			}
		}		
	}
}

stock void DoubleJump(int client)
{
	int fCurFlags = GetEntityFlags(client);
	int fCurButtons = GetEntityFlags(client);
	
	if(g_iLastFlags[client] & FL_ONGROUND)
	{
		if(!(fCurFlags & FL_ONGROUND) && !(g_iLastButtons[client] & IN_JUMP) && (fCurButtons & IN_JUMP))
		{
			OriginalJump(client);
		}
	}
	else if(fCurFlags & FL_ONGROUND)
	{
		LandedClient(client);
	}
	else if(!(g_iLastButtons[client] & IN_JUMP) && (fCurButtons & IN_JUMP))
	{
		ReJump(client);
	}
	
	g_iLastFlags[client] = fCurFlags;
	g_iLastButtons[client] = fCurButtons;
}

stock void OriginalJump(int client) 
{
	g_iJumps[client]++;
}

stock void LandedClient(int client) 
{
	g_iJumps[client] = 0;
}

stock void ReJump(int client) 
{
	if ( 1 <= g_iJumps[client] <= g_iJumpMax) 
	{						
		g_iJumps[client]++;
		float vVel[3];
		GetEntPropVector(client, Prop_Data, "m_vecVelocity", vVel);
		
		vVel[2] = g_flBoost;
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vVel);
	}
}