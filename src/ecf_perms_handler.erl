-module(ecf_perms_handler).

-behaviour(cowboy_handler).

-export([init/2, terminate/3]).


init(Req, State) ->
    Type = cowboy_req:binding(type, Req),
    Id = cowboy_req:binding(id, Req),
    case ecf_utils:check_user_session(Req) of
        undefined ->
            % guests don't need to, and shouldn't, check permissions
            Req2 = ecf_utils:reply_status(401, undefined, perms_401, Req),
            {ok, Req2, State};
        User ->
            case cowboy_req:method(Req) of
                <<"GET">> ->
                    #{perm := PermBin} = cowboy_req:match_qs([{perm, nonempty}],
                                                             Req),
                    try binary_to_existing_atom(PermBin, latin1) of
                        Perm ->
                            B = check_perm(User, Type, Id, Perm),
                            Map = #{success => B},
                            Req2 = cowboy_req:reply(200,
                                                    #{<<"content-type">>
                                                      => <<"application/json">>},
                                                    jiffy:encode(Map),
                                                    Req),
                            {ok, Req2, State}
                    catch
                        exception:badarg ->
                            Map = #{success => false},
                            Req2 = cowboy_req:reply(400,
                                                    #{<<"content-type">>
                                                      => <<"application/json">>},
                                                    jiffy:encode(Map),
                                                    Req),
                            {ok, Req2, State}
                    end;
                <<"PATCH">> ->
                    case check_perm(User, Type, Id, edit_perms) of
                        true ->
                            {ok, Body, Req2} = cowboy_req:read_body(Req),
                            Json = jiffy:decode(Body, [return_maps]),
                            Class = get_class(Json),
                            Mode = get_mode(Json),
                            Set = get_set(Json),
                            ok = case Type of
                                     <<"global">> ->
                                         ecf_perms:edit_global_perm(Class, Mode,
                                                                    Set);
                                     <<"forum">> ->
                                         ecf_forum:edit_perm(Id, Class, Mode,
                                                             Set);
                                     <<"thread">> ->
                                         ecf_thread:edit_perm(Id, Class, Mode,
                                                              Set);
                                     <<"group">> ->
                                         ecf_group:edit_perm(Id, Class, Mode,
                                                             Set)
                                 end,
                            Req3 = cowboy_req:reply(204, Req2),
                            {ok, Req3, State};
                        false ->
                            Req2 = cowboy_req:reply(403, Req),
                            {ok, Req2, State}
                    end;
                <<"DELETE">> ->
                    case check_perm(User, Type, Id, edit_perms) of
                        true ->
                            {ok, Body, Req2} = cowboy_req:read_body(Req),
                            Json = jiffy:decode(Body, [return_maps]),
                            Class = get_class(Json),
                            Mode = get_mode(Json),
                            ok = case Type of
                                     <<"global">> ->
                                         ecf_perms:remove_global_perm(Class, Mode);
                                     <<"forum">> ->
                                         ecf_forum:remove_perm(Id, Class, Mode);
                                     <<"thread">> ->
                                         ecf_thread:remove_perm(Id, Class, Mode);
                                     <<"group">> ->
                                         ecf_group:remove_perm(Id, Class, Mode)
                                 end,
                            Req3 = cowboy_req:reply(204, Req2),
                            {ok, Req3, State};
                        false ->
                            Req2 = cowboy_req:reply(403, Req),
                            {ok, Req2, State}
                    end
            end
    end.


terminate(_Reason, _Req, _State) ->
    ok.

%% Internal functions

-spec check_perm(ecf_user:user(), binary(), non_neg_integer(),
                 ecf_perms:mode()) -> boolean().
check_perm(User, <<"global">>, _, Mode) ->
    ecf_perms:check_perm_global(User, Mode);
check_perm(User, <<"forum">>, Id, Mode) ->
    Forum = ecf_forum:get_forum(Id),
    ecf_perms:check_perm_forum(User, Forum, Mode);
check_perm(User, <<"thread">>, Id, Mode) ->
    Thread = ecf_thread:get_thread(Id),
    ecf_perms:check_perm_thread(User, Thread, Mode);
check_perm(User, <<"group">>, Id, Mode) ->
    Group = ecf_group:get_group(Id),
    ecf_perms:check_perm_group(User, Group, Mode).

get_class(Json) ->
    case maps:get(<<"class">>, Json) of
        [<<"user">>, Id] ->
            {user, Id};
        [<<"group">>, Id] ->
            {group, Id};
        <<"others">> ->
            others
    end.

get_mode(Json) ->
    binary_to_existing_atom(maps:get(<<"mode">>, Json), latin1).

get_set(Json) ->
    case maps:get(<<"set">>, Json) of
        <<"allow">> -> allow;
        <<"deny">> -> deny
    end.

