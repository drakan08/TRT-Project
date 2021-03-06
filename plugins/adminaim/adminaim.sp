#include <sourcemod>
#include <sdkhooks>

public Plugin myinfo = 
{
	name = "Admin Aim",
	author = "DarkGL edited by BloodTiger",
	description = "Admin Aim",
	version = "1.0",
	url = "http://darkgl.pl"
}

bool aimOn[ 33 ];

public OnPluginStart(){
	RegAdminCmd("aim", aimMenu , ADMFLAG_BAN , "Admin Aim Menu" );
}

public bool OnClientConnect(client, String:rejectmsg[], maxlen){
	aimOn[ client ] = false;
	
	return true;
}

public OnClientDisconnect( client ){
	aimOn[ client ] = false;
	
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public OnClientPutInServer(client){
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action aimMenu(int client, int args)
{
	createMenu(client);
	
	return Plugin_Handled;
}

public createMenu( client ){
	Handle menuHandle = CreateMenu( MenuHandler );
	
	SetMenuTitle( menuHandle, "Admin Aim Menu" );
	
	for( new iPlayer = 1 ; iPlayer <= MaxClients ; iPlayer++ ){
		if( !IsClientConnected( iPlayer ) ){
			continue;
		}
		
		new String:szName[ 64 ];
		
		GetClientName( iPlayer , szName , sizeof( szName ) );
		
		new String:szPlayer[ 128 ],
			String:szDisplay[ 128 ];
			
		Format( szPlayer , sizeof( szPlayer ) , "%d" , iPlayer );
		Format( szDisplay , sizeof( szDisplay ) , "%s: %s" , szName , aimOn[ iPlayer ] ? "On":"Off" );
		
		AddMenuItem( menuHandle , szPlayer , szDisplay );
	}
	
	DisplayMenu( menuHandle, client, MENU_TIME_FOREVER );
}

public MenuHandler(Handle menu, MenuAction:action, param1, param2){
	
	if (action == MenuAction_Select){
		new String: szInfo[32];
		
		GetMenuItem( menu, param2, szInfo, sizeof( szInfo ) - 1 );
		
		new iPlayer = StringToInt( szInfo );
		
		if( !IsClientInGame( iPlayer ) ){
			return;
		}
		
		aimOn[ iPlayer ] = !aimOn[ iPlayer ];
		
		CloseHandle(menu);
		
		createMenu( param1 );
	}
	else if (action == MenuAction_End){
		
		CloseHandle(menu);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom){
	if( !IsClientValid( victim ) || !IsClientValid( attacker ) ){
		return Plugin_Continue;
	}
	
	if( aimOn[ attacker ] ){
		damagetype = 34603010;
		
		damage = float(GetClientHealth(victim) + GetClientArmor(victim));
		
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

stock bool IsClientValid(int client)
{
	if(client > 0 && client <= MaxClients && IsClientInGame(client))
		return true;
	return false;
}
