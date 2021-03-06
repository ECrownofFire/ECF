-module(ecf_user).

-include_lib("stdlib/include/qlc.hrl").

-export_type([id/0, user/0]).

-define(HASH(X), enacl:pwhash_str(X, moderate, interactive)).

-define(SESSION_LENGTH, 32).

%%% Wrapper for user type

-type id() :: non_neg_integer().

-export([create_table/1,
         new_user/3,
         get_user/1, get_user_by_name/1, get_user_by_email/1,
         edit_name/2, edit_email/2, edit_pass/2, new_session/1, reset_session/2,
         enable_user/1, disable_user/1,
         add_group/2, remove_group/2,
         edit_bio/2, edit_bday/2,
         edit_title/2, edit_loc/2,
         add_post/2,
         delete_user/1,
         check_session/2, refresh_session/2, check_pass/2, fake_hash/0,
         id/1, name/1, enabled/1, email/1,
         joined/1, groups/1, bday/1, title/1, bio/1, loc/1, posts/1,
         last_post/1]).

-record(ecf_user,
        {id     :: id(),
         name   :: binary(),
         enabled:: boolean(),
         session:: [{binary(), integer()}],
         pass   :: binary(),
         email  :: binary(),
         joined :: erlang:timestamp(),
         groups = [] :: [ecf_group:id()],
         bday   = undefined :: calendar:datetime() | undefined,
         title  = <<"">> :: binary(),
         bio    = <<"">> :: binary(),
         loc    = <<"">> :: binary(),
         posts = 0 :: non_neg_integer(),
         last_post :: erlang:timestamp()}).
-opaque user() :: #ecf_user{}.

-spec create_table([node()]) -> ok.
create_table(Nodes) ->
    {atomic, ok} = mnesia:create_table(ecf_user,
                        [{attributes, record_info(fields, ecf_user)},
                         {disc_copies, Nodes}]),
    Key = crypto:strong_rand_bytes(32),
    ecf_global:put(encryption_key, Key),
    ok.

-spec new_user(binary(), binary(), binary()) ->
    {id(), binary()} | {error, atom()}.
new_user(Name, Pass, Email0) ->
    Email = string:trim(Email0),
    Hash = hash_pass(Pass),
    Sess = make_session(),
    F = fun() ->
                case get_user_by_name(Name) of
                    undefined ->
                        case get_user_by_email(Email) of
                            undefined ->
                                Id = ecf_db:get_new_id(ecf_user),
                                Time = erlang:timestamp(),
                                ok = mnesia:write(
                                       #ecf_user{id=Id, name=Name, enabled=true,
                                                 pass=Hash, session=[Sess],
                                                 email=Email, joined=Time,
                                                 last_post=Time}),
                                % All users are in the basic group
                                ok = ecf_group:add_member(1, Id),
                                {S, _} = Sess,
                                {Id, S};
                            _ ->
                                {error, email_taken}
                        end;
                    _ ->
                        {error, username_taken}
                end
        end,
    case mnesia:activity(transaction, F) of
        {error, _} = Err ->
            Err;
        {Id, _} = Res ->
            ok = ecf_email:send_confirmation_email(get_user(Id)),
            Res
    end.

-spec get_user(id()) -> user() | undefined.
get_user(Id) ->
    F = fun() ->
                mnesia:read({ecf_user, Id})
        end,
    case mnesia:activity(transaction, F) of
        [User] ->
            User;
        _ ->
            undefined
    end.

% Case insensitive search
-spec get_user_by_name(binary()) -> user() | undefined.
get_user_by_name(Name) ->
    F = fun() ->
            qlc:e(qlc:q(
                [X || X = #ecf_user{name=N} <- mnesia:table(ecf_user),
                      string:equal(Name, N, true)]))
        end,
    case mnesia:activity(transaction, F) of
        [User] ->
            User;
        _ ->
            undefined
    end.

% Case insensitive search
-spec get_user_by_email(binary()) -> user() | undefined.
get_user_by_email(Email) ->
    F = fun() ->
            qlc:e(qlc:q(
                [X || X = #ecf_user{email=E} <- mnesia:table(ecf_user),
                      string:equal(Email, E, true)]))
        end,
    case mnesia:activity(transaction, F) of
        [User] ->
            User;
        _ ->
            undefined
    end.


-spec edit_name(id(), binary()) -> binary() | {error, username_taken}.
edit_name(Id, Name) ->
    Sess = make_session(),
    F = fun() ->
                case get_user_by_name(Name) of
                    undefined ->
                        [User] = mnesia:wread({ecf_user, Id}),
                        ok = mnesia:write(User#ecf_user{name=Name,session=[Sess]}),
                        {S, _} = Sess,
                        S;
                    _ ->
                        {error, username_taken}
                end
        end,
    mnesia:activity(transaction, F).

-spec edit_email(id(), binary()) -> binary() | {error, email_taken}.
edit_email(Id, Email) ->
    Sess = make_session(),
    F = fun() ->
                case get_user_by_email(Email) of
                    undefined ->
                        [User] = mnesia:wread({ecf_user, Id}),
                        ok = mnesia:write(User#ecf_user{email=Email,session=[Sess]}),
                        ok = ecf_group:remove_member(2, Id),
                        {S, _} = Sess,
                        S;
                    _ ->
                        {error, email_taken}
                end
        end,
    case mnesia:activity(transaction, F) of
        {error, _} = Err ->
            Err;
        Res ->
            ok = ecf_email:send_confirmation_email(get_user(Id)),
            Res
    end.

-spec edit_pass(id(), binary()) -> binary().
edit_pass(Id, NewPass) ->
    Hash = hash_pass(NewPass),
    Sess = make_session(),
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                ok = mnesia:write(User#ecf_user{pass=Hash,session=[Sess]}),
                {Session, _} = Sess,
                Session
        end,
    mnesia:activity(transaction, F).


-spec new_session(id()) -> binary().
new_session(Id) ->
    Session = make_session(),
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                New = [Session|User#ecf_user.session],
                mnesia:write(User#ecf_user{session=New})
        end,
    ok = mnesia:activity(transaction, F),
    {S, _} = Session,
    S.

-spec reset_session(id(), binary()) -> ok.
reset_session(Id, Session) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                New = lists:keydelete(Session, 1, User#ecf_user.session),
                mnesia:write(User#ecf_user{session=New})
        end,
    mnesia:activity(transaction, F).

-spec clean_sessions(id()) -> user().
clean_sessions(Id) ->
    F = fun() ->
            [User] = mnesia:wread({ecf_user, Id}),
            Old = User#ecf_user.session,
            New = lists:filter(fun clean_sess/1, Old),
            case length(Old) =:= length(New) of
                false ->
                    NewUser = User#ecf_user{session=New},
                    mnesia:write(NewUser),
                    NewUser;
                true ->
                    User
            end
        end,
    mnesia:activity(transaction, F).

clean_sess({_, Time}) ->
    Remaining = Time - erlang:system_time(second),
    Remaining > 0.

-spec check_session(id(), binary()) -> boolean().
check_session(Id, Session) ->
    User = clean_sessions(Id),
    case lists:keyfind(Session, 1, User#ecf_user.session) of
        {_, _} ->
            enabled(User);
        false ->
            false
    end.

-spec refresh_session(id(), binary()) -> binary() | false | ok.
refresh_session(Id, Old) ->
    F =
    fun() ->
        User = clean_sessions(Id),
        case lists:keyfind(Old, 1, User#ecf_user.session) of
            false ->
                false;
            {Old, Time} ->
                Limit = application:get_env(ecf, minutes_refresh, 10080) * 60,
                Now = erlang:system_time(second),
                case Time - Now of
                    N when N < Limit ->
                        % force expire old session in 15 minutes
                        List = lists:keyreplace(Old, 1,
                                                User#ecf_user.session,
                                                {Old, Now + 15 * 60}),
                        mnesia:write(User#ecf_user{session=List}),
                        new_session(Id);
                    _ ->
                        ok
                end
        end
    end,
    mnesia:activity(transaction, F).


-spec enable_user(id()) -> ok.
enable_user(Id) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{enabled=true})
        end,
    mnesia:activity(transaction, F).

-spec disable_user(id()) -> ok.
disable_user(Id) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{enabled=false})
        end,
    mnesia:activity(transaction, F).


-spec add_group(id(), ecf_group:id()) -> ok.
add_group(Id, Group) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                NewList = [Group|groups(User)],
                mnesia:write(User#ecf_user{groups=NewList})
        end,
    mnesia:activity(transaction, F).

-spec remove_group(id(), ecf_group:id()) -> ok.
remove_group(Id, Group) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                NewList = lists:delete(Group, groups(User)),
                mnesia:write(User#ecf_user{groups=NewList})
        end,
    mnesia:activity(transaction, F).

-spec edit_bio(id(), binary()) -> ok.
edit_bio(Id, Bio) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{bio=Bio})
        end,
    mnesia:activity(transaction, F).

-spec edit_bday(id(), calendar:datetime() | undefined) -> ok.
edit_bday(Id, Bday) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{bday=Bday})
        end,
    mnesia:activity(transaction, F).

-spec edit_title(id(), binary()) -> ok.
edit_title(Id, Title) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{title=Title})
        end,
    mnesia:activity(transaction, F).

-spec edit_loc(id(), binary()) -> ok.
edit_loc(Id, Loc) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                mnesia:write(User#ecf_user{loc=Loc})
        end,
    mnesia:activity(transaction, F).

-spec add_post(id(), erlang:timestamp()) -> ok.
add_post(Id, Time) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                New = User#ecf_user.posts + 1,
                mnesia:write(User#ecf_user{posts=New, last_post=Time})
        end,
    mnesia:activity(transaction, F).


-spec delete_user(id()) -> ok.
delete_user(Id) ->
    F = fun() ->
                [User] = mnesia:wread({ecf_user, Id}),
                [ecf_group:remove_member(Group, Id) || Group <- groups(User)],
                mnesia:delete({ecf_user, Id})
        end,
    mnesia:activity(transaction, F).


-spec id(user()) -> id().
id(User) ->
    User#ecf_user.id.

-spec name(user()) -> binary().
name(User) ->
    User#ecf_user.name.

-spec enabled(user()) -> boolean().
enabled(User) ->
    User#ecf_user.enabled.

-spec check_pass(user(), binary()) -> boolean().
check_pass(User, Pass) ->
    <<Nonce:24/binary, Enc/binary>> = User#ecf_user.pass,
    Key = ecf_global:get(encryption_key),
    case enacl:aead_xchacha20poly1305_decrypt(Key, Nonce, <<>>, Enc) of
        Hash when is_binary(Hash) ->
            enacl:pwhash_str_verify(Hash, Pass);
        _ ->
            fake_hash(),
            false
    end.

-spec hash_pass(binary()) -> binary().
hash_pass(Pass) ->
    {ok, Hash} = ?HASH(Pass),
    Nonce = crypto:strong_rand_bytes(24),
    Key = ecf_global:get(encryption_key),
    Enc = enacl:aead_xchacha20poly1305_encrypt(Key, Nonce, <<>>, Hash),
    <<Nonce:24/binary, Enc/binary>>.

% Fakes hashing for invalid logins
-spec fake_hash() -> ok.
fake_hash() ->
    Test = <<"$argon2id$v=19$m=65536,t=3,p=1$1uZRoN+31tWAp5568l4NdQ$K41NbPMWptYR+KDI2iAHmP0qoeL1agZqptVwuSdpUGA">>,
    enacl:pwhash_str_verify(Test, <<"badpassword">>),
    ok.

-spec email(user()) -> binary().
email(User) ->
    User#ecf_user.email.

-spec joined(user()) -> erlang:timestamp().
joined(User) ->
    User#ecf_user.joined.

-spec groups(user()) -> [ecf_group:id()].
groups(User) ->
    User#ecf_user.groups.

-spec bday(user()) -> calendar:datetime() | undefined.
bday(User) ->
    User#ecf_user.bday.

-spec title(user()) -> binary().
title(User) ->
    User#ecf_user.title.

-spec bio(user()) -> binary().
bio(User) ->
    User#ecf_user.bio.

-spec loc(user()) -> binary().
loc(User) ->
    User#ecf_user.loc.

-spec posts(user()) -> non_neg_integer().
posts(User) ->
    User#ecf_user.posts.

-spec last_post(user()) -> erlang:timestamp().
last_post(User) ->
    User#ecf_user.last_post.

%%% UTILITIES

make_session() ->
    Session = crypto:strong_rand_bytes(?SESSION_LENGTH),
    Time = erlang:system_time(second),
    Limit = application:get_env(ecf, minutes_session, 20160) * 60,
    Expire = Time + Limit,
    {Session, Expire}.

