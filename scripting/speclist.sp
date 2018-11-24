#pragma semicolon 1
#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <clientprefs>

#define SPECMODE_NONE 0
#define SPECMODE_FIRSTPERSON 4
#define SPECMODE_3RDPERSON 5
#define SPECMODE_FREELOOK 6

#define UPDATE_INTERVAL 0.1
#define PLUGIN_VERSION "1.1.4"

Handle
	  HudHintTimers[MAXPLAYERS+1]
	, g_hSpecListCookie;
ConVar
	  sm_speclist_enabled
	, sm_speclist_allowed
	, sm_speclist_adminonly
	, sm_speclist_noadmins;
bool
	  g_Enabled
	, g_AdminOnly
	, g_NoAdmins
	, g_SpecHide[MAXPLAYERS+1]
	, g_bInScore[MAXPLAYERS+1]
	, g_bLateLoad;
 
public Plugin myinfo = {
	name = "Spectator List",
	author = "GoD-Tony, updated by JoinedSenses",
	description = "View who is spectating you",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	g_bLateLoad = late;
	return APLRes_Success;
}
 
public void OnPluginStart() {
	CreateConVar("sm_speclist_version", PLUGIN_VERSION, "Spectator List Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	sm_speclist_enabled = CreateConVar("sm_speclist_enabled","1","Enables the spectator list for all players by default.");
	sm_speclist_allowed = CreateConVar("sm_speclist_allowed","1","Allows players to enable spectator list manually when disabled by default.");
	sm_speclist_adminonly = CreateConVar("sm_speclist_adminonly","0","Only admins can use the features of this plugin.");
	sm_speclist_noadmins = CreateConVar("sm_speclist_noadmins", "1","Don't show non-admins that admins are spectating them.");
	
	RegConsoleCmd("sm_speclist", Command_SpecList);
	RegAdminCmd("sm_spechide", cmdSpecHide, ADMFLAG_GENERIC);
	
	HookConVarChange(sm_speclist_enabled, OnConVarChange);
	HookConVarChange(sm_speclist_adminonly, OnConVarChange);
	HookConVarChange(sm_speclist_noadmins, OnConVarChange);
	g_hSpecListCookie = RegClientCookie("SpecList_cookie", "Spectator List Cookie", CookieAccess_Protected);	
	g_Enabled = sm_speclist_enabled.BoolValue;
	g_AdminOnly = sm_speclist_adminonly.BoolValue;
	g_NoAdmins = sm_speclist_noadmins.BoolValue;
	
	AutoExecConfig(true, "plugin.speclist");

	if (g_bLateLoad) {
		for (int i = 0; i <= MaxClients; i++) {
			OnClientPostAdminCheck(i);
			OnClientCookiesCached(i);
		}
	}
}

public Action OnPlayerRunCmd(int client, int& buttons) {
	if (HudHintTimers[client] != null) {
		g_bInScore[client] = (buttons & IN_SCORE) > 0;
	}
}

public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == sm_speclist_enabled) {
		g_Enabled = sm_speclist_enabled.BoolValue;
		if (g_Enabled) {
			// Enable timers on all players in game.
			for(int i = 1; i <= MaxClients; i++)  {
				if (!IsClientInGame(i)) {
					continue;
				}
				CreateHudHintTimer(i);
			}
		}
		else {
			// Kill all of the active timers.
			for(int i = 1; i <= MaxClients; i++) {
				KillHudHintTimer(i);
			}
		}
	}
	else if (convar == sm_speclist_adminonly) {
		g_AdminOnly = sm_speclist_adminonly.BoolValue;
		if (g_AdminOnly) {
			// Kill all of the active timers.
			for(int i = 1; i <= MaxClients; i++) {
				KillHudHintTimer(i);
			}
			// Enable timers on all admins in game.
			for(int i = 1; i <= MaxClients; i++)  {
				if (!IsClientInGame(i)) {
					continue;
				}
				CreateHudHintTimer(i);
			}
		}
	}
	else if (convar == sm_speclist_noadmins) {
		g_NoAdmins = sm_speclist_noadmins.BoolValue;
		if (g_NoAdmins) {
			// Kill all of the active timers.
			for(int i = 1; i <= MaxClients; i++) {
				KillHudHintTimer(i);
			}
				
			// Enable timers on all admins in game.
			for(int i = 1; i <= MaxClients; i++) {
				if (!IsClientInGame(i)) {
					continue;
				}
				CreateHudHintTimer(i);
			}
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	if (g_Enabled && IsValidClient(client)) {
		CreateHudHintTimer(client);
	}
}
public void OnClientCookiesCached(int client) {
	if (g_Enabled && IsValidClient(client)) {
		char sValue[8];
		GetClientCookie(client, g_hSpecListCookie, sValue, sizeof(sValue));
		g_SpecHide[client] = (sValue[0] != '\0' && StringToInt(sValue));
	}
}  
public void OnClientDisconnect(int client) {
	if (g_Enabled && IsValidClient(client)) {
		KillHudHintTimer(client);
	}
}
public Action cmdSpecHide(int client, int args) {
	if (!g_Enabled) {
		ReplyToCommand(client, "Speclist disabled");
		return Plugin_Handled;
	}
	g_SpecHide[client] = !g_SpecHide[client];
	PrintToChat(client, "\x01[\x05SM\x01] You are now \x05%s \x01in spec list", (g_SpecHide[client] ? "hidden" : "visible"));
	SetClientCookie(client, g_hSpecListCookie, g_SpecHide[client] ? "1" : "0");
	return Plugin_Handled;
}
// Using 'sm_speclist' to toggle the spectator list per player.
public Action Command_SpecList(int client, int args) {
	if (HudHintTimers[client] != null) {
		KillHudHintTimer(client);
		ReplyToCommand(client, "[SM] Spectator list disabled.");
	}
	else if (g_Enabled || GetConVarBool(sm_speclist_allowed)) {
		CreateHudHintTimer(client);
		ReplyToCommand(client, "[SM] Spectator list enabled.");
	}
	return Plugin_Handled;
}

void CreateHudHintTimer(int client) {
	if (!g_AdminOnly || (g_AdminOnly && IsPlayerAdmin(client))) {
		HudHintTimers[client] = CreateTimer(UPDATE_INTERVAL, Timer_UpdateHudHint, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

void KillHudHintTimer(int client) {
	if (HudHintTimers[client] != null) {
		KillTimer(HudHintTimers[client]);
		HudHintTimers[client] = null;
	}
}

public Action Timer_UpdateHudHint(Handle timer, any client) {
	if (g_bInScore[client]) {
		return Plugin_Continue;
	}
	int iSpecModeUser = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int iSpecMode;
	int iTarget;
	int iTargetUser;
	bool bDisplayHint;
	
	char szText[254];
	szText[0] = '\0';
	
	// Dealing with a client who is in the game and playing.
	if (IsPlayerAlive(client)) {
		for(int i = 1; i <= MaxClients; i++)  {
			if (!IsClientInGame(i) || !IsClientObserver(i)) {
				continue;
			}
			
			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if(!IsPlayerAdmin(client) && (g_NoAdmins && IsPlayerAdmin(i) && g_SpecHide[i])) {
				continue;
			}
			iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			
			// The client isn't spectating any one person, so ignore them.
			if (iSpecMode != SPECMODE_FIRSTPERSON && iSpecMode != SPECMODE_3RDPERSON) {
				continue;
			}
			
			// Find out who the client is spectating.
			iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			
			// Are they spectating our player?
			if (iTarget == client) {
				if (g_SpecHide[i])
					Format(szText, sizeof(szText), "%s%N [Hidden]\n", szText, i);
				else
					Format(szText, sizeof(szText), "%s%N\n", szText, i);
				bDisplayHint = true;
			}
		}
	}
	else if (iSpecModeUser == SPECMODE_FIRSTPERSON || iSpecModeUser == SPECMODE_3RDPERSON) {
		// Find out who the User is spectating.
		iTargetUser = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
		
		if (MaxClients >= iTargetUser > 0)
			Format(szText, sizeof(szText), "Spectating %N:\n", iTargetUser);
		
		for(int  i = 1; i <= MaxClients; i++)  {			
			if (!IsClientInGame(i) || !IsClientObserver(i)) {
				continue;
			}
			
			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if(!IsPlayerAdmin(client) && (g_NoAdmins && IsPlayerAdmin(i) && g_SpecHide[i])) {
				continue;
			}
			iSpecMode = GetEntProp(i, Prop_Send, "m_iObserverMode");
			
			// The client isn't spectating any one person, so ignore them.
			if (iSpecMode != SPECMODE_FIRSTPERSON && iSpecMode != SPECMODE_3RDPERSON) {
				continue;
			}
			// Find out who the client is spectating.
			iTarget = GetEntPropEnt(i, Prop_Send, "m_hObserverTarget");
			
			// Are they spectating the same player as User?
			if (iTarget == iTargetUser) {
				Format(szText, sizeof(szText), "%s%N%s\n", szText, i, g_SpecHide[i] ? " [Hidden]" : "");
			}
		}
	}
	
	/* We do this to prevent displaying a message
		to a player if no one is spectating them anyway. */
	if (bDisplayHint) {
		Format(szText, sizeof(szText), "Spectating %N:\n%s", client, szText);
		bDisplayHint = false;
	}
			
	// Send our message
	Handle hBuffer = StartMessageOne("KeyHintText", client); 
	BfWriteByte(hBuffer, 1); 
	BfWriteString(hBuffer, szText); 
	EndMessage();
	
	return Plugin_Continue;
}

bool IsPlayerAdmin(int client) {
	return (IsClientInGame(client) && CheckCommandAccess(client, "show_spectate", ADMFLAG_GENERIC));
}

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientConnected(client) && !IsFakeClient(client));
}