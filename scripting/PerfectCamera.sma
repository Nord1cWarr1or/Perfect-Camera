/*  *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *
*                                                                               *
*   Plugin: Perfect Camera                                                      *
*                                                                               *
*   Official repository: https://github.com/Nord1cWarr1or/Perfect-Camera        *
*   Official plugin support: https://dev-cs.ru/threads/15444/                   *
*   Contacts of the author: Telegram: @NordicWarrior                            *
*                                                                               *
*   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *       *
*                                                                               *
*   Плагин: Идеальная камера                                                    *
*                                                                               *
*   Официальный репозиторий: https://github.com/Nord1cWarr1or/Perfect-Camera    *
*   Официальная поддержка плагина: https://dev-cs.ru/threads/15444/             *
*   Связь с автором: Telegram: @NordicWarrior                                   *
*                                                                               *
*   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   *   */

#include <amxmodx>
#include <fakemeta>
#include <reapi>
#include <nvault_array>
#include <xs>

new const PLUGIN_VERSION[] = "0.2.5";

// <-- SETTINGS -->

new const TOGGLE_CAM_CMDS[][] = 
{
    "say /cam",
    "say_team /cam",
    "say .сфь",
    "say_team .сфь"
};

new const CAM_SETTINGS_CMDS[][] =
{
    "say /camset",
    "say_team /camset"
};

// A model that will be 100% in your server's precache
new const CAMERA_MODEL[] = "models/hgibs.mdl";

// <-- END OF SETTINGS --> 

// https://dev-cs.ru/threads/222/post-76443
#define register_cmd_list(%0,%1,%2) for (new i = 0; i < sizeof(%1); i++) register_%0(%1[i], %2)

#define CheckBit(%0,%1) (%0 & (1 << %1))
#define SetBit(%0,%1) (%0 |= (1 << %1))
#define ClearBit(%0,%1) (%0 &= ~(1 << %1))
#define ToggleBit(%0,%1) (%0 ^= (1 << %1))

new const CAMERA_CUSTOM_CLASSNAME[]     = "perfect_camera";

enum _:XYZ { Float:X, Float:Y, Float:Z };

enum _:CVARS
{
    Float:DEFAULT_DISTANCE,
    Float:MINIMUM_DISTANCE,
    Float:MAXIMUM_DISTANCE,
    NVAULT_PRUNE_DAYS,
    DEFAULT_TRANSPARENCY
};

new bool:g_bIsPlayerNoTransparent[MAX_PLAYERS + 1];
new bool:g_bCamAlwaysInThirdPerson[MAX_PLAYERS + 1];
new Float:g_flCamDistance[MAX_PLAYERS + 1];

new g_bitInThirdPerson;

new g_CvarValue[CVARS];
new g_iVautHandle = INVALID_HANDLE;

new g_iCameraEnt[MAX_PLAYERS + 1] = { NULLENT, ... };

public plugin_init()
{
    register_plugin("Perfect Camera", PLUGIN_VERSION, "Nordic Warrior");

    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_PlayerSpawn_Post", true);
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_PlayerKilled_Post", true);

    register_message(get_user_msgid("SetFOV"), "message_SetFOV");

    register_cmd_list(clcmd, TOGGLE_CAM_CMDS, "cmdToggleCam", ADMIN_ALL);
    register_cmd_list(clcmd, CAM_SETTINGS_CMDS, "cmdOpenCamMenu", ADMIN_ALL);

    CreateCvars();
    AutoExecConfig(true, "PerfectCamera");

    g_iVautHandle = nvault_open(CAMERA_CUSTOM_CLASSNAME);

    if(g_iVautHandle != INVALID_HANDLE)
    {
        nvault_prune(g_iVautHandle, 0, get_systime() - g_CvarValue[NVAULT_PRUNE_DAYS] * 86400);
    }
}

public OnConfigsExecuted()
{
    arrayset(g_flCamDistance, g_CvarValue[DEFAULT_DISTANCE], sizeof g_flCamDistance);

    register_cvar("PerfectCamera_version", PLUGIN_VERSION, FCVAR_SERVER|FCVAR_SPONLY|FCVAR_UNLOGGED);
}

public client_putinserver(id)
{
    if(g_iVautHandle == INVALID_HANDLE)
        return;

    new szAuthID[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuthID, charsmax(szAuthID));

    new Data[4];
    nvault_get_array(g_iVautHandle, szAuthID, Data, charsmax(Data));

    g_bIsPlayerNoTransparent[id] = bool:Data[0];
    g_bCamAlwaysInThirdPerson[id] = bool:Data[2];

    if(Data[1])
    {
        g_flCamDistance[id] = float(Data[1]);
    }

    if(g_bCamAlwaysInThirdPerson[id])
    {
        SetBit(g_bitInThirdPerson, id);
        Toggle_AddToFullPack();
    }
}

public client_disconnected(id)
{
    RemoveCam(id, false);

    g_bIsPlayerNoTransparent[id] = g_bCamAlwaysInThirdPerson[id] = false;
    g_flCamDistance[id] = g_CvarValue[DEFAULT_DISTANCE];

    ClearBit(g_bitInThirdPerson, id);
    Toggle_AddToFullPack();

    if(g_iVautHandle == INVALID_HANDLE)
        return;

    new szAuthID[MAX_AUTHID_LENGTH];
    get_user_authid(id, szAuthID, charsmax(szAuthID));

    new Data[4];

    Data[0] = g_bIsPlayerNoTransparent[id];
    Data[1] = floatround(g_flCamDistance[id]);
    Data[2] = g_bCamAlwaysInThirdPerson[id];

    nvault_set_array(g_iVautHandle, szAuthID, Data, charsmax(Data));
}

public cmdToggleCam(const id)
{
    ToggleBit(g_bitInThirdPerson, id);
    Toggle_AddToFullPack();

    if(is_user_alive(id))
    {
        if(CheckBit(g_bitInThirdPerson, id))
        {
            CreateCam(id);
            client_cmd(id, "stopsound");
        }
        else
        {
            RemoveCam(id, true);
            client_cmd(id, "stopsound");
        }
    }
    else
    {
        client_print_color(id, print_team_default, "^4* ^1Вы переключили ^3режим камеры^1.")
    }
}

public cmdOpenCamMenu(const id)
{
    new iMenu = menu_create(fmt("Настройки камеры \rv%s", PLUGIN_VERSION), "CamMenu_handler");

    menu_additem(iMenu, fmt("Прозрачная модель: \d[%s\d]^n", g_bIsPlayerNoTransparent[id] ? "\rНет" : "\yДа"));

    menu_addtext(iMenu, fmt("\wТекущая дистанция: \d[\y%0.f\d]", g_flCamDistance[id]), .slot = 0);
    menu_additem(iMenu, "Дальше \d[\y+\d]");
    menu_additem(iMenu, "Ближе \d[\r–\d]^n");

    menu_additem(iMenu, fmt("Вид от 3-го лица всегда активен: \d[%s\d]", g_bCamAlwaysInThirdPerson[id] ? "\yДа" : "\rНет"));
    
    menu_setprop(iMenu, MPROP_PERPAGE, 0);
    menu_setprop(iMenu, MPROP_EXIT, MEXIT_FORCE);

    menu_addblank2(iMenu);
    menu_addblank2(iMenu);
    menu_addblank2(iMenu);
    menu_addblank2(iMenu);
    menu_addblank2(iMenu);

    menu_setprop(iMenu, MPROP_EXITNAME, "Выход");

    menu_display(id, iMenu);
    return PLUGIN_HANDLED;
}

public CamMenu_handler(const id, iMenu, iItem)
{
    switch(iItem)
    {
        case MENU_EXIT:
        {
            menu_destroy(iMenu);
            return;
        }

        case 0: g_bIsPlayerNoTransparent[id] = !g_bIsPlayerNoTransparent[id];
        case 1: g_flCamDistance[id] = floatmin(g_CvarValue[MAXIMUM_DISTANCE], g_flCamDistance[id] + 5.0);
        case 2: g_flCamDistance[id] = floatmax(g_CvarValue[MINIMUM_DISTANCE], g_flCamDistance[id] - 5.0);
        case 3: g_bCamAlwaysInThirdPerson[id] = !g_bCamAlwaysInThirdPerson[id];
    }

    menu_destroy(iMenu);
    cmdOpenCamMenu(id);
}

public RG_PlayerSpawn_Post(const id)
{
    if(!is_user_alive(id) || is_user_connecting(id))
        return;

    if(CheckBit(g_bitInThirdPerson, id) && is_nullent(g_iCameraEnt[id]))
    {
        CreateCam(id);
    }
    else
    {
        RemoveCam(id, true);
    }
}

public RG_PlayerKilled_Post(const id)
{
    if(!is_user_connected(id))
        return;

    if(CheckBit(g_bitInThirdPerson, id))
    {
        RemoveCam(id, true);
    } 
}

CreateCam(const id)
{
    new iCameraEnt = rg_create_entity("trigger_camera");

    if(is_nullent(iCameraEnt))
        return;

    static iModelIndex;

    if(!iModelIndex)
        iModelIndex = engfunc(EngFunc_ModelIndex, CAMERA_MODEL);

    set_entvar(iCameraEnt, var_classname, CAMERA_CUSTOM_CLASSNAME);
    set_entvar(iCameraEnt, var_modelindex, iModelIndex);
    set_entvar(iCameraEnt, var_owner, id);
    set_entvar(iCameraEnt, var_movetype, MOVETYPE_NOCLIP);
    set_entvar(iCameraEnt, var_rendermode, kRenderTransColor);
    
    engset_view(id, iCameraEnt);

    set_entvar(iCameraEnt, var_nextthink, get_gametime() + 0.01);
    SetThink(iCameraEnt, "OnCamThink");

    g_iCameraEnt[id] = iCameraEnt;
}

RemoveCam(id, bool:bAttachViewToPlayer)
{
    if(bAttachViewToPlayer)
    {
        engset_view(id, id);
    }

    new iCameraEnt = MaxClients;

    while((iCameraEnt = rg_find_ent_by_class(iCameraEnt, CAMERA_CUSTOM_CLASSNAME)))
    {
        if(is_nullent(iCameraEnt))
            continue;

        if(get_entvar(iCameraEnt, var_owner) == id && g_iCameraEnt[id] == iCameraEnt)
        {
            rg_remove_entity(iCameraEnt);

            g_iCameraEnt[id] = NULLENT;
            break;
        }
    }
}

public OnCamThink(iCameraEnt)
{
    new id = get_entvar(iCameraEnt, var_owner);

    if(!is_user_alive(id) || is_nullent(iCameraEnt))
        return;

    new Float:flPlayerOrigin[XYZ], Float:flCamOrigin[XYZ], Float:flVecPlayerAngles[XYZ], Float:flVecCamAngles[XYZ];

    get_entvar(id, var_origin, flPlayerOrigin);
    get_entvar(id, var_view_ofs, flVecPlayerAngles);

    flPlayerOrigin[Z] += flVecPlayerAngles[Z];

    get_entvar(id, var_v_angle, flVecPlayerAngles);

    angle_vector(flVecPlayerAngles, ANGLEVECTOR_FORWARD, flVecCamAngles);

    xs_vec_sub_scaled(flPlayerOrigin, flVecCamAngles, g_flCamDistance[id], flCamOrigin);

    engfunc(EngFunc_TraceLine, flPlayerOrigin, flCamOrigin, IGNORE_MONSTERS, id, 0);

    new Float:flFraction;
    get_tr2(0, TR_flFraction, flFraction);

    xs_vec_sub_scaled(flPlayerOrigin, flVecCamAngles, flFraction * g_flCamDistance[id], flCamOrigin);

    set_entvar(iCameraEnt, var_origin, flCamOrigin);
    set_entvar(iCameraEnt, var_angles, flVecPlayerAngles);

    set_entvar(iCameraEnt, var_nextthink, get_gametime() + 0.01);
}

public FM_AddToFullPack_Post(es, e, ent, host, hostflags, player, pset)
{
    if(ent == host && CheckBit(g_bitInThirdPerson, ent) && !g_bIsPlayerNoTransparent[ent])
    {
        set_es(es, ES_RenderMode, kRenderTransTexture);
        set_es(es, ES_RenderAmt, g_CvarValue[DEFAULT_TRANSPARENCY]);
    }
    else if(CheckBit(g_bitInThirdPerson, host) && get_es(es, ES_AimEnt) == host && !g_bIsPlayerNoTransparent[host])
    {
        set_es(es, ES_RenderMode, kRenderTransTexture);
        set_es(es, ES_RenderAmt, g_CvarValue[DEFAULT_TRANSPARENCY]);
    }
}

public message_SetFOV(iMsgID, iMsgDest, id)
{
    static const iMsgArg_FOV = 1;

    if(!CheckBit(g_bitInThirdPerson, id) || !is_user_connected(id) || g_iCameraEnt[id] == NULLENT)
        return;

    new iPlayerFOV = get_msg_arg_int(iMsgArg_FOV);

    switch(iPlayerFOV)
    {
        case DEFAULT_LARGE_AWP_ZOOM, DEFAULT_LARGE_OTHER_SNIPERS_ZOOM, DEFAULT_SMALL_SNIPERS_ZOOM: engset_view(id, id);
        case DEFAULT_NO_ZOOM: engset_view(id, g_iCameraEnt[id]);
    }
}

Toggle_AddToFullPack()
{
    static AddToFullPack;

    if(g_bitInThirdPerson && !AddToFullPack)
    {
        AddToFullPack = register_forward(FM_AddToFullPack, "FM_AddToFullPack_Post", true);
    }
    else if(!g_bitInThirdPerson && AddToFullPack)
    {
        unregister_forward(FM_AddToFullPack, AddToFullPack, true);
        AddToFullPack = 0;
    }
}

CreateCvars()
{
    bind_pcvar_float(create_cvar("amx_cam_def_distance", "150.0",
        .description = "Дистанция для камеры по умолчанию"),
        g_CvarValue[DEFAULT_DISTANCE]);

    bind_pcvar_float(create_cvar("amx_cam_min_distance", "50.0",
        .description = "Минимальная дистанция для камеры"),
        g_CvarValue[MINIMUM_DISTANCE]);

    bind_pcvar_float(create_cvar("amx_cam_max_distance", "350.0",
        .description = "Максимальная дистанция для камеры"),
        g_CvarValue[MAXIMUM_DISTANCE]);

    bind_pcvar_num(create_cvar("amx_cam_prune_days", "21",
        .description = "После скольки дней удалять настройки игрока, если он не заходит"),
        g_CvarValue[NVAULT_PRUNE_DAYS]);

    bind_pcvar_num(create_cvar("amx_cam_def_amt", "100",
        .description = "Процент прозрачности модели при активной прозрачности"),
        g_CvarValue[DEFAULT_TRANSPARENCY]);
}

public plugin_end()
{
    if(g_iVautHandle != INVALID_HANDLE)
    {
        nvault_close(g_iVautHandle);
    }
}
