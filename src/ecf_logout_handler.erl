-module(ecf_logout_handler).
-behaviour(cowboy_handler).

-export([init/2, terminate/3]).

init(Req = #{method := <<"POST">>}, State) ->
    User = ecf_utils:check_user_session(Req),
    #{url := Url} = cowboy_req:match_qs([{url, [], <<"">>}], Req),
    #{session := SessEnc} = cowboy_req:match_cookies([session], Req),
    Sess = base64:decode(SessEnc),
    ok = ecf_user:reset_session(ecf_user:id(User), Sess),
    Req2 = cowboy_req:set_resp_cookie(<<"session">>, <<"0">>, Req,
                                      #{max_age => 0}),
    Req3 = cowboy_req:set_resp_cookie(<<"user">>, <<"0">>, Req2,
                                      #{max_age => 0}),
    Req4 = cowboy_req:reply(200,
                            #{<<"content-type">> => <<"text/html">>},
                            ecf_generators:generate(logout, undefined, Url),
                            Req3),
    {ok, Req4, State};
init(Req = #{method := <<"GET">>}, State) ->
    User = ecf_utils:check_user_session(Req),
    #{url := Url} = cowboy_req:match_qs([{url, [], <<"">>}], Req),
    Html = ecf_generators:generate(logout, User, Url),
    Req2 = cowboy_req:reply(200, #{<<"content-type">> => <<"text/html">>},
                            Html, Req),
    {ok, Req2, State};
init(Req, State) ->
    User = ecf_utils:check_user_session(Req),
    Req2 = cowboy_req:reply(405,
                            #{<<"content-type">> => <<"text/html">>,
                              <<"allow">> => <<"GET, POST">>},
                            ecf_generators:generate(405, User, {logout, false}),
                            Req),
    {ok, Req2, State}.

terminate(_Reason, _Req, _State) ->
    ok.

