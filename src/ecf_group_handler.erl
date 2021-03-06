-module(ecf_group_handler).

-behaviour(cowboy_handler).

-export([init/2]).

init(Req = #{method := <<"GET">>}, State) ->
    User = ecf_utils:check_user_session(Req),
    Req2 = case cowboy_req:binding(id, Req, -1) of
               -1 ->
                   Groups = ecf_group:filter_groups(User, ecf_group:get_groups()),
                   Html = ecf_generators:generate(groups, User, Groups),
                   cowboy_req:reply(200, #{<<"content-type">> => <<"text/html">>},
                                    Html, Req);
               Id ->
                   case ecf_group:get_group(Id) of
                       undefined ->
                           ecf_utils:reply_status(404, User, false, Req);
                       Group ->
                           case ecf_perms:check_perm_group(User, Group,
                                                           view_group) of
                               true ->
                                   Html = ecf_generators:generate(group, User, Group),
                                   cowboy_req:reply(200, #{<<"content-type">>
                                                           => <<"text/html">>},
                                                    Html, Req);
                               false ->
                                   ecf_utils:reply_status(403, User,
                                                          view_group_403, Req)
                           end
                   end
           end,
    {ok, Req2, State};
init(Req = #{method := <<"POST">>}, State) ->
    User = ecf_utils:check_user_session(Req),
    Req2 = handle_post(User, Req, cowboy_req:binding(action, Req)),
    {ok, Req2, State}.

handle_post(undefined, Req, _) ->
    ecf_utils:reply_status(401, undefined, group_401, Req);
handle_post(User, Req, undefined) ->
    ecf_utils:reply_status(404, User, false, Req);
handle_post(User, Req, <<"create">>) ->
    case ecf_perms:check_perm_global(User, create_group) of
        true ->
            L = [name, desc],
            {ok, M, Req2} = cowboy_req:read_and_match_urlencoded_body(L, Req),
            #{name := Name, desc := Desc} = M,
            Id = ecf_group:new_group(Name, Desc),
            redirect(Id, Req2);
        false ->
            ecf_utils:reply_status(403, User, create_group_403, Req)
    end;
handle_post(User, Req0, <<"delete">>) ->
    {ok, M, Req} = cowboy_req:read_and_match_urlencoded_body([{id, int}], Req0),
    #{id := Id} = M,
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case Id >= 4
                 andalso ecf_perms:check_perm_group(User, Group, delete_group) of
                true ->
                    ok = ecf_group:delete_group(Id),
                    ecf_utils:reply_redirect(303, <<"/group">>, Req);
                false ->
                    ecf_utils:reply_status(403, User, delete_group_403, Req)
            end
    end;
handle_post(User, Req0, <<"edit">>) ->
    L = [{id, int}, name, desc],
    {ok, M, Req} = cowboy_req:read_and_match_urlencoded_body(L, Req0),
    #{id := Id, name := Name, desc := Desc} = M,
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case ecf_perms:check_perm_group(User, Group, edit_group) of
                true ->
                    ok = ecf_group:edit_name(Id, Name),
                    ok = ecf_group:edit_desc(Id, Desc),
                    redirect(Id, Req);
                false ->
                    ecf_utils:reply_status(403, User, edit_group_403, Req)
            end
    end;
handle_post(User, Req0, <<"join">>) ->
    {ok, #{id := Id}, Req} = cowboy_req:read_and_match_urlencoded_body([{id, int}], Req0),
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case Id >= 4
                 andalso ecf_perms:check_perm_group(User, Group, join_group) of
                true ->
                    ok = ecf_group:add_member(Id, ecf_user:id(User)),
                    redirect(Id, Req);
                false ->
                    ecf_utils:reply_status(403, User, join_group_403, Req)
            end
    end;
handle_post(User, Req0, <<"leave">>) ->
    {ok, #{id := Id}, Req} = cowboy_req:read_and_match_urlencoded_body([{id, int}], Req0),
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case Id >= 4
                 andalso ecf_perms:check_perm_group(User, Group, leave_group) of
                true ->
                    ok = ecf_group:remove_member(Id, ecf_user:id(User)),
                    redirect(Id, Req);
                false ->
                    ecf_utils:reply_status(403, User, leave_group_403, Req)
            end
    end;
handle_post(User, Req0, <<"add">>) ->
    {ok, M, Req} = cowboy_req:read_and_match_urlencoded_body([{id, int}, {user, int}], Req0),
    #{id := Id, user := U} = M,
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case Id =/= 1 andalso Id =/= 3
                 andalso ecf_perms:check_perm_group(User, Group, manage_group) of
                true ->
                    case ecf_user:get_user(U) of
                        undefined ->
                            ecf_utils:reply_status(400, User, invalid_user, Req);
                        _ ->
                            ok = ecf_group:add_member(Id, U),
                            redirect_user(U, Req)
                    end;
                false ->
                    ecf_utils:reply_status(403, User, manage_group_403, Req)
            end
    end;
handle_post(User, Req0, <<"remove">>) ->
    {ok, M, Req} = cowboy_req:read_and_match_urlencoded_body([{id, int}, {user, int}], Req0),
    #{id := Id, user := U} = M,
    case ecf_group:get_group(Id) of
        undefined ->
            ecf_utils:reply_status(400, User, invalid_group, Req);
        Group ->
            case Id =/= 1 andalso Id =/= 3
                 andalso ecf_perms:check_perm_group(User, Group, manage_group) of
                true ->
                    case ecf_user:get_user(U) of
                        undefined ->
                            ecf_utils:reply_status(400, User, invalid_user, Req);
                        _ ->
                            ok = ecf_group:remove_member(Id, U),
                            redirect_user(U, Req)
                    end;
                false ->
                    ecf_utils:reply_status(403, User, manage_group_403, Req)
            end
    end.

redirect(Id, Req) ->
    ecf_utils:reply_redirect(303, ["/group/", integer_to_binary(Id)], Req).

redirect_user(Id, Req) ->
    ecf_utils:reply_redirect(303, ["/user/", integer_to_binary(Id)], Req).

