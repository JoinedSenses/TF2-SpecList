#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <clientprefs>

#define SPECMODE_NONE 0
#define SPECMODE_FIRSTPERSON 4
#define SPECMODE_3RDPERSON 5
#define SPECMODE_FREELOOK 6

#define UPDATE_INTERVAL 0.1
#define PLUGIN_VERSION "1.1.5"

Handle
	  g_hHudHintTimers[MAXPLAYERS+1]
	, g_hSpecListCookie;
ConVar
	  g_cvarEnabled
	, g_cvarAllowed
	, g_cvarAdminOnly
	, g_cvarAdminHide;
bool
	  g_bEnabled
	, g_bAdminOnly
	, g_bAdminHide
	, g_bSpecHide[MAXPLAYERS+1]
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
	CreateConVar("sm_speclist_version", PLUGIN_VERSION, "Spectator List Version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);
	g_cvarEnabled = CreateConVar("sm_speclist_enabled", "1", "Enables the spectator list for all players by default.");
	g_cvarAllowed = CreateConVar("sm_speclist_allowed", "1", "Allows players to enable spectator list manually when disabled by default.");
	g_cvarAdminOnly = CreateConVar("sm_speclist_adminonly", "0", "Only admins can use the features of this plugin.");
	g_cvarAdminHide = CreateConVar("sm_speclist_adminhide", "1", "Allow admins to hide themselves from non-admins in speclist.");

	RegConsoleCmd("sm_speclist", cmdSpecList);
	RegAdminCmd("sm_spechide", cmdSpecHide, ADMFLAG_GENERIC);

	g_cvarEnabled.AddChangeHook(OnConVarChange);
	g_cvarAdminOnly.AddChangeHook(OnConVarChange);
	g_cvarAdminHide.AddChangeHook(OnConVarChange);

	g_hSpecListCookie = RegClientCookie("SpecList_cookie", "Spectator List Cookie", CookieAccess_Protected);

	AutoExecConfig();

	g_bEnabled = g_cvarEnabled.BoolValue;
	g_bAdminOnly = g_cvarAdminOnly.BoolValue;
	g_bAdminHide = g_cvarAdminHide.BoolValue;

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i)) {
				OnClientPostAdminCheck(i);
				OnClientCookiesCached(i);
			}
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons) {
	if (g_hHudHintTimers[client] != null) {
		g_bInScore[client] = (buttons & IN_SCORE) > 0;
	}
}

public void OnConVarChange(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (convar == g_cvarEnabled) {
		g_bEnabled = g_cvarEnabled.BoolValue;
		if (g_bEnabled) {
			// Enable timers on all players in game.
			for (int i = 1; i <= MaxClients; i++)  {
				if (IsClientInGame(i)) {
					CreateHudHintTimer(i);
				}
			}
		}
		else {
			// Kill all of the active timers.
			for (int i = 1; i <= MaxClients; i++) {
				delete g_hHudHintTimers[i];
			}
		}
	}
	else if (convar == g_cvarAdminOnly) {
		g_bAdminOnly = g_cvarAdminOnly.BoolValue;
		if (g_bAdminOnly) {
			// Kill all of the active timers.
			for (int i = 1; i <= MaxClients; i++) {
				delete g_hHudHintTimers[i];

				if (IsClientInGame(i)) {
					CreateHudHintTimer(i);
				}
			}
		}
	}
	else if (convar == g_cvarAdminHide) {
		g_bAdminHide = g_cvarAdminHide.BoolValue;
		if (g_bAdminHide) {
			// Kill all of the active timers.
			for (int i = 1; i <= MaxClients; i++) {
				delete g_hHudHintTimers[i];
				// Enable timers on all admins in game.
				if (IsClientInGame(i)) {
					CreateHudHintTimer(i);
				}
			}
		}
	}
}

public void OnClientPostAdminCheck(int client) {
	if (g_bEnabled && IsValidClient(client)) {
		CreateHudHintTimer(client);
	}
}

public void OnClientCookiesCached(int client) {
	if (g_bEnabled && IsValidClient(client)) {
		char sValue[8];
		GetClientCookie(client, g_hSpecListCookie, sValue, sizeof(sValue));
		g_bSpecHide[client] = (sValue[0] != '\0' && StringToInt(sValue));
	}
}

public void OnClientDisconnect(int client) {
	if (g_bEnabled && IsValidClient(client)) {
		delete g_hHudHintTimers[client];
	}
}

public Action cmdSpecHide(int client, int args) {
	if (!g_bEnabled) {
		ReplyToCommand(client, "Speclist disabled");
		return Plugin_Handled;
	}
	if (!g_bAdminHide) {
		ReplyToCommand(client, "This feature is disabled.");
		return Plugin_Handled;
	}

	g_bSpecHide[client] = !g_bSpecHide[client];
	PrintToChat(client, "\x01[\x05SM\x01] You are now \x05%s \x01in spec list", (g_bSpecHide[client] ? "hidden" : "visible"));
	SetClientCookie(client, g_hSpecListCookie, g_bSpecHide[client] ? "1" : "0");
	return Plugin_Handled;
}

// Using 'sm_speclist' to toggle the spectator list per player.
public Action cmdSpecList(int client, int args) {
	if (g_hHudHintTimers[client] != null) {
		delete g_hHudHintTimers[client];
		ReplyToCommand(client, "[SM] Spectator list disabled.");
	}
	else if (g_bEnabled || g_cvarAllowed.BoolValue) {
		CreateHudHintTimer(client);
		ReplyToCommand(client, "[SM] Spectator list enabled.");
	}
	return Plugin_Handled;
}

void CreateHudHintTimer(int client) {
	if (!g_bAdminOnly || (g_bAdminOnly && IsPlayerAdmin(client))) {
		g_hHudHintTimers[client] = CreateTimer(UPDATE_INTERVAL, Timer_UpdateHudHint, client, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action Timer_UpdateHudHint(Handle timer, any client) {
	if (g_bInScore[client]) {
		return Plugin_Continue;
	}

	int iSpecModeUser = GetEntProp(client, Prop_Send, "m_iObserverMode");
	int iSpecMode;
	int iTarget;
	int iTargetUser;
	bool bDisplayHint;

	char szText[254];

	// Dealing with a client who is in the game and playing.
	if (IsPlayerAlive(client)) {
		for (int i = 1; i <= MaxClients; i++)  {
			if (!IsClientInGame(i) || !IsClientObserver(i)) {
				continue;
			}

			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if (!IsPlayerAdmin(client) && (g_bAdminHide && IsPlayerAdmin(i) && g_bSpecHide[i])) {
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
				Format(szText, sizeof(szText), "%s%N%s\n", szText, i, g_bSpecHide[i] ? " [Hidden]" : "");
				bDisplayHint = true;
			}
		}
	}
	else if (iSpecModeUser == SPECMODE_FIRSTPERSON || iSpecModeUser == SPECMODE_3RDPERSON) {
		// Find out who the User is spectating.
		iTargetUser = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

		if (0 < iTargetUser <= MaxClients) {
			Format(szText, sizeof(szText), "Spectating %N:\n", iTargetUser);
		}

		for (int  i = 1; i <= MaxClients; i++)  {
			if (!IsClientInGame(i) || !IsClientObserver(i)) {
				continue;
			}

			// The 'client' is not an admin and do not display admins is enabled and the client (i) is an admin, so ignore them.
			if (!IsPlayerAdmin(client) && (g_bAdminHide && IsPlayerAdmin(i) && g_bSpecHide[i])) {
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
				Format(szText, sizeof(szText), "%s%N%s\n", szText, i, g_bSpecHide[i] ? " [Hidden]" : "");
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
	BfWrite hBuffer = UserMessageToBfWrite(StartMessageOne("KeyHintText", client));
	hBuffer.WriteByte(1);
	hBuffer.WriteString(szText);
	EndMessage();

	return Plugin_Continue;
}

bool IsPlayerAdmin(int client) {
	return (IsClientInGame(client) && CheckCommandAccess(client, "show_spectate", ADMFLAG_GENERIC));
}

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}