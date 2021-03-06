-module(ecf_generators).

-define(GRAVATAR_URL, <<"https://gravatar.com/avatar/">>).
-define(GRAVATAR_OPTIONS, <<"?s=100&d=identicon">>).

-export([generate/3]).

-spec generate(atom() | integer(), ecf_user:user() | undefined, term()) -> iodata().
generate(main, User, Forums) ->
    Vars = get_vars(User, ""),
    ForumList = forum_list(Forums),
    Vars2 = [{forum_list, ForumList}|Vars],
    {ok, Res} = ecf_main_dtl:render(Vars2),
    Res;
generate(admin, User, _) ->
    Vars = get_vars(User, "Admin"),
    Forums = ecf_forum:order_forums(ecf_forum:get_forums()),
    CanReorder = ecf_perms:check_perm_global(User, reorder_forums),
    CanCreate = ecf_perms:check_perm_global(User, create_forum),
    CanEditPerms = ecf_perms:check_perm_global(User, edit_perms),
    FVar = forum_list(Forums),
    Vars2 = case CanEditPerms of
                true ->
                    Groups = lists:keysort(2, ecf_group:get_groups()),
                    GroupList = group_list(Groups),
                    PermList = perm_list(ecf_perms:get_global_perms()),
                    [{perm_list, PermList}, {group_list, GroupList} | Vars];
                false ->
                    Vars
            end,
    CanViewBans = ecf_perms:check_perm_global(User, view_bans),
    Vars3 = [{forums, FVar}
             , {can_reorder, CanReorder}
             , {can_create_forum, CanCreate}
             , {can_edit_perms, CanEditPerms}
             , {can_view_bans, CanViewBans}
             | Vars2],
    {ok, Res} = ecf_admin_dtl:render(Vars3),
    Res;
generate(login, User, {Captcha, Url, Type}) ->
    Vars = get_vars(User, "Login"),
    Message = login_message(User, Type),
    {ok, Key} = application:get_env(ecf, recaptcha_key),
    Vars2 = [{captcha, Captcha}, {message, Message},
             {recaptcha_key, Key}, {url, Url}
             | Vars],
    {ok, Res} = ecf_login_dtl:render(Vars2),
    Res;
generate(forgot_pw, undefined, Type) ->
    Vars = get_vars(undefined, "Forgot Password"),
    {ok, Message} = application:get_env(ecf, Type),
    {ok, Key} = application:get_env(ecf, recaptcha_key),
    Vars2 = [{message, Message}, {recaptcha_key, Key} | Vars],
    {ok, Res} = ecf_forgot_pw_dtl:render(Vars2),
    Res;
generate(reset_pw, User, {Captcha, Type, Code}) ->
    Vars = get_vars(User, "Reset Password"),
    {ok, Message} = application:get_env(ecf, Type),
    {ok, Key} = application:get_env(ecf, recaptcha_key),
    Vars2 = [{captcha, Captcha}, {message, Message},
             {recaptcha_key, Key}, {code, Code}
             | Vars],
    {ok, Res} = ecf_reset_pw_dtl:render(Vars2),
    Res;
generate(change_pw, User, Type) ->
    Vars = get_vars(User, "Change Password"),
    Message = application:get_env(ecf, Type, <<"Change your password here.">>),
    Vars2 = [{message, Message} | Vars],
    {ok, Res} = ecf_change_pw_dtl:render(Vars2),
    Res;
generate(logout, undefined, Url) ->
    Vars = get_vars(undefined, "Logout"),
    Message = application:get_env(ecf, logout_message,
                                  <<"You've successfully been logged out.">>),
    Vars2 = [{message, Message}, {url, Url}|Vars],
    {ok, Res} = ecf_logout_dtl:render(Vars2),
    Res;
generate(logout, User, Url) ->
    Vars = get_vars(User, "Logout"),
    Vars2 = [{url, Url} | Vars],
    {ok, Res} = ecf_logout_dtl:render(Vars2),
    Res;
generate(register, _, {Type, BaseVars}) ->
    Vars = [get_vars(undefined, "Register") | BaseVars],
    Message = application:get_env(ecf, Type, <<"Please register.">>),
    {ok, Key} = application:get_env(ecf, recaptcha_key),
    Vars2 = [{message, Message}, {recaptcha_key, Key} | Vars],
    {ok, Res} = ecf_register_dtl:render(Vars2),
    Res;
generate(confirm_email, User, Code) ->
    Vars = get_vars(User, "Confirm Email"),
    Vars2 = [{code, Code} | Vars],
    {ok, Res} = ecf_confirm_email_dtl:render(Vars2),
    Res;
generate(confirmed_email, User, _) ->
    Vars = get_vars(User, "Email Confirmed"),
    {ok, Res} = ecf_confirmed_email_dtl:render(Vars),
    Res;
generate(user, User, Profile) ->
    Vars = get_vars(User, ["Profile of ", ecf_user:name(Profile)]),
    Self = User =/= undefined andalso ecf_user:id(User) =:= ecf_user:id(Profile),
    CanEdit = Self orelse ecf_perms:check_perm_global(User, edit_user),
    CanBan = ecf_ban:check_perm(User, Profile),
    AddList = groups_add(User, Profile),
    RemList = groups_rem(User, Profile),
    Vars2 = [{can_edit, CanEdit}
             , {can_ban, CanBan}
             , {profile, user_profile(Profile)}
             , {add_list, AddList}
             , {rem_list, RemList}
             , {ban, ban(ecf_ban:check_ban(ecf_user:id(Profile)))}
             | Vars],
    {ok, Res} = ecf_user_dtl:render(Vars2),
    Res;
generate(groups, User, Groups) ->
    Vars = get_vars(User, "Groups"),
    GroupsSorted = lists:keysort(2, Groups),
    GroupList = group_list(User, GroupsSorted),
    CanCreate = ecf_perms:check_perm_global(User, create_group),
    Vars2 = [{group_list, GroupList},
             {can_create, CanCreate}
             | Vars],
    {ok, Res} = ecf_groups_dtl:render(Vars2),
    Res;
generate(group, User, Group) ->
    Vars = get_vars(User, ["Group: ", ecf_group:name(Group)]),
    MemberList = users(ecf_group:members(Group)),
    GroupV = [{member_list, MemberList}|group(Group)],
    CanEdit = ecf_perms:check_perm_group(User, Group, edit_group),
    CanDelete = ecf_group:id(Group) >= 4
                andalso ecf_perms:check_perm_group(User, Group, delete_group),
    Vars2 = [{group, GroupV},
             {can_edit, CanEdit},
             {can_delete, CanDelete}
             | Vars],
    {ok, Res} = ecf_group_dtl:render(Vars2),
    Res;
generate(forum, User, {Forum, Threads, Page, Last}) ->
    Vars = get_vars(User, ecf_forum:name(Forum)),
    ForumV = forum(Forum),
    ThreadList = thread_list(Threads, ecf_forum:pins(Forum)),
    CanEdit = ecf_forum:id(Forum) >= 1
              andalso ecf_perms:check_perm_forum(User, Forum, edit_forum),
    CanDelete = ecf_forum:id(Forum) >= 1
                andalso ecf_perms:check_perm_forum(User, Forum, delete_forum),
    CanCreate = ecf_perms:check_perm_forum(User, Forum, create_thread),
    Vars2 = [{forum, ForumV},
             {thread_list, ThreadList},
             {can_edit, CanEdit},
             {can_delete, CanDelete},
             {can_create_thread, CanCreate},
             {page, Page},
             {page_last, Last}
             | Vars],
    {ok, Res} = ecf_forum_dtl:render(Vars2),
    Res;
generate(thread, User, {Forum, Thread, Posts, Page, Last}) ->
    Vars = get_vars(User, ecf_thread:title(Thread)),
    ForumV = forum(Forum),
    ThreadV = thread(Thread, ecf_forum:pins(Forum)),
    PostList = post_list(Posts),
    CreatePost = ecf_perms:check_perm_thread(User, Thread, create_post),
    EditPosts = ecf_perms:check_perm_thread(User, Thread, edit_post),
    EditOwnPosts = ecf_perms:check_perm_thread(User, Thread, edit_own_post),
    DeletePosts = ecf_perms:check_perm_thread(User, Thread, delete_post),
    DeleteOwnPosts = ecf_perms:check_perm_thread(User, Thread, delete_own_post),
    EditThread = ecf_perms:check_perm_thread(User, Thread, edit_thread),
    DeleteThread = ecf_perms:check_perm_thread(User, Thread, delete_thread),
    EditPerms = ecf_perms:check_perm_thread(User, Thread, edit_perms),
    PinThread = ecf_perms:check_perm_thread(User, Thread, pin_thread),
    TagThread = ecf_perms:check_perm_thread(User, Thread, tag_thread),
    Users = pm_users(Thread),
    Vars2 = [{forum, ForumV},
             {thread, ThreadV},
             {post_list, PostList},
             {can_create_post, CreatePost},
             {can_edit_posts, EditPosts},
             {can_edit_own_posts, EditOwnPosts},
             {can_delete_posts, DeletePosts},
             {can_delete_own_posts, DeleteOwnPosts},
             {can_edit_thread, EditThread},
             {can_delete_thread, DeleteThread},
             {can_edit_perms, EditPerms},
             {can_tag_thread, TagThread},
             {can_pin_thread, PinThread},
             {page, Page},
             {page_last, Last},
             {pm_users, Users}
             | Vars],
    {ok, Res} = ecf_thread_dtl:render(Vars2),
    Res;
generate(post_edit, User, {Thread, Post}) ->
    Vars = get_vars(User, "Edit Post"),
    PerPage = application:get_env(ecf, posts_per_page, 40),
    Page = integer_to_binary(ecf_post:id(Post) div PerPage + 1),
    Vars2 = [{thread, thread(Thread)}, {post, post(Post)}, {page, Page}
             | Vars],
    {ok, Res} = ecf_post_edit_dtl:render(Vars2),
    Res;
generate(user_edit, User, Profile) ->
    Vars = get_vars(User, "Edit Profile"),
    ProfileV = user_profile(Profile),
    Vars2 = [{profile, ProfileV} | Vars],
    {ok, Res} = ecf_user_edit_dtl:render(Vars2),
    Res;
generate(ban, User, {Target, Ban}) ->
    Vars = get_vars(User, "Ban User"),
    Vars2 = [{target, user(Target)}
             , {ban, ban(Ban)}
             | Vars],
    {ok, Res} = ecf_ban_dtl:render(Vars2),
    Res;
generate(unban, User, {Target, Ban}) ->
    Vars = get_vars(User, "Unban User"),
    Vars2 = [{target, user(Target)}
             , {ban, ban(Ban)}
             | Vars],
    {ok, Res} = ecf_unban_dtl:render(Vars2),
    Res;
generate(bans, User, Bans) ->
    Vars = get_vars(User, "Bans"),
    Vars2 = [{ban_list, ban_list(Bans)} | Vars],
    {ok, Res} = ecf_bans_dtl:render(Vars2),
    Res;
generate(Status, User, {Type, Storage})
  when is_integer(Status), Status >= 400, Status =< 499 ->
    Desc = status_desc(Status),
    Vars = get_vars(User, [integer_to_binary(Status), " - ", Desc]),
    Message = case Type of
                  false -> false;
                  _ -> application:get_env(ecf, Type, Desc)
              end,
    Vars2 = [{code, integer_to_binary(Status)},
             {desc, Desc},
             {message, Message},
             {storage, Storage}
             | Vars],
    {ok, Res} = ecf_error_dtl:render(Vars2),
    Res.


get_vars(User, Title) ->
    {ok, Base} = application:get_env(ecf, base_url),
    CanViewUsers = ecf_perms:check_perm_global(User, view_user),
    [{base, Base},
     {title, get_title(Title)},
     {can_view_users, CanViewUsers},
     {user, user_profile(User)}].

-spec get_title(iodata()) -> iodata().
get_title(String) ->
    {ok, ForumName} = application:get_env(ecf, forum_name),
    case string:is_empty(String) of
        false ->
            [ForumName, " - ", String];
        true ->
            ForumName
    end.

users(Users) ->
    [user(X) || X <- Users].

-spec user(ecf_user:user()) -> [{atom(), term()}];
          (ecf_user:id()) -> [{atom(), term()}];
          (undefined) -> false.
user(undefined) ->
    false;
user(Id) when is_integer(Id) ->
    user(get_user(Id));
user(User) ->
    [{id, ecf_user:id(User)},
     {name, ecf_user:name(User)},
     {joined, iso8601:format(ecf_user:joined(User))},
     {title, ecf_user:title(User)},
     {posts, integer_to_binary(ecf_user:posts(User))}].

% grabs additional vars when looking at a user's profile page
user_profile(undefined) ->
    false;
user_profile(User) ->
    U = user(User),
    FormatStr = "~4.10.0B-~2.10.0B-~2.10.0B",
    Bday = case ecf_user:bday(User) of
               {{Y,M,D},_} -> io_lib:format(FormatStr, [Y, M, D]);
               _ -> ""
           end,
    [{email, ecf_user:email(User)}
     , {bday, Bday}
     , {bio, ecf_user:bio(User)}
     , {loc, ecf_user:loc(User)}
     , {group_list, group_list(User, ecf_user:groups(User))}
     | U].

ban_list(Bans) ->
    [ban(X) || X <- Bans].

ban(undefined) ->
    false;
ban(Ban) ->
    Until = case ecf_ban:until(Ban) of
                permanent ->
                    <<"permanent">>;
                T ->
                  iso8601:format(T)
            end,
    [{user, user(ecf_ban:user(Ban))},
     {by, user(ecf_ban:by(Ban))},
     {reason, ecf_ban:reason(Ban)},
     {time, iso8601:format(ecf_ban:time(Ban))},
     {until, Until}].


perm_list(Perms) ->
    [perm(X) || X <- Perms].

perm(Perm) ->
    Mode = ecf_perms:mode(Perm),
    ModeBin = atom_to_binary(Mode, utf8),
    Allow = ecf_perms:allow(Perm),
    Deny = ecf_perms:deny(Perm),
    AllowList = [class(X) || X <- Allow],
    DenyList = [class(X) || X <- Deny],
    [{mode, ModeBin},
     {name, mode_name(ModeBin)},
     {allow, AllowList},
     {deny, DenyList}].

% necessary because the title filter doesn't work for some reason
mode_name(Mode) ->
    Words = string:split(Mode, "_", all),
    lists:join(" ", [string:titlecase(X) || X <- Words]).

class(others) ->
    [{type, <<"others">>},
     {name, <<"Others">>}];
class({user, Id}) ->
    [{type, <<"user">>},
     {id, Id},
     {name, ecf_user:name(get_user(Id))}];
class({group, Id}) ->
    [{type, <<"group">>},
     {id, Id},
     {name, ecf_group:name(get_group(Id))}].

login_message(undefined, Type) ->
    application:get_env(ecf, Type, <<"Please login.">>);
login_message(_User, _) ->
    application:get_env(ecf, already_logged_in,
                        <<"You're already logged in!">>).


forum_list(Forums) ->
    [forum(X) || X <- Forums].

forum(Forum) ->
    [{id, integer_to_binary(ecf_forum:id(Forum))},
     {name, ecf_forum:name(Forum)},
     {desc, ecf_forum:desc(Forum)},
     {threads, integer_to_binary(ecf_forum:threads(Forum))},
     {posts, integer_to_binary(ecf_forum:posts(Forum))}].

group_list(User, Groups) ->
    [group(User, X) || X <- Groups].

group(User, Group) when is_integer(Group) ->
    group(User, get_group(Group));
group(User, Group) ->
    Id = ecf_group:id(Group),
    InGroup = lists:member(Id, ecf_user:groups(User)),
    CanJoin = Id >= 4
              andalso not InGroup
              andalso ecf_perms:check_perm_group(User, Group, join_group),
    CanLeave = Id >= 4
               andalso InGroup
               andalso ecf_perms:check_perm_group(User, Group, leave_group),
     [{can_leave, CanLeave},
      {can_join, CanJoin}
      | group(Group)].

group_list(Groups) ->
    [group(X) || X <- Groups].

group(Group) ->
    [{id, integer_to_binary(ecf_group:id(Group))},
     {name, ecf_group:name(Group)},
     {desc, ecf_group:desc(Group)},
     {members, integer_to_binary(length(ecf_group:members(Group)))}].


groups_add(User, Profile) ->
    Gs = ecf_user:groups(Profile),
    F1 = fun(G) -> not lists:member(ecf_group:id(G), Gs)
                   andalso ecf_group:id(G) =/= 1
                   andalso ecf_group:id(G) =/= 3
         end,
    Groups = lists:filter(F1, ecf_group:get_groups()),
    F2 = fun(G) -> ecf_perms:check_perm_group(User, G, manage_group) end,
    group_list(lists:filter(F2, Groups)).

groups_rem(User, Profile) ->
    Gs = ecf_user:groups(Profile),
    F1 = fun(G) -> lists:member(ecf_group:id(G), Gs)
                   andalso ecf_group:id(G) =/= 1
                   andalso ecf_group:id(G) =/= 3
         end,
    Groups = lists:filter(F1, ecf_group:get_groups()),
    F2 = fun(G) -> ecf_perms:check_perm_group(User, G, manage_group) end,
    group_list(lists:filter(F2, Groups)).


thread_list(Threads, Pins) ->
    [thread(X, Pins) || X <- Threads].

thread(Thread, Pins) ->
    Id = ecf_thread:id(Thread),
    [{pinned, lists:member(Id, Pins)} | thread(Thread)].

thread(Thread) ->
    Id = ecf_thread:id(Thread),
    LastId = ecf_thread:last(Thread),
    LastPost = ecf_post:get_post(Id, LastId),
    LastPostTime = ecf_post:time(LastPost),
    LastPoster = user(ecf_post:poster(LastPost)),
    Creator = user(ecf_thread:creator(Thread)),
    Tags = tags(ecf_tag:get_tags(Id)),
    Views = ecf_thread:views(Thread),
    [{id, integer_to_binary(Id)},
     {title, ecf_thread:title(Thread)},
     {replies, integer_to_binary(LastId)},
     {creator, Creator},
     {last_time, iso8601:format(LastPostTime)},
     {last_poster, LastPoster},
     {tags, Tags},
     {views, integer_to_binary(Views)}].

tags(Tags) ->
    [tag(X) || X <- Tags].

tag(Tag) ->
    [{name, ecf_tag:name(Tag)}].

pm_users(Thread) ->
    case ecf_thread:forum(Thread) of
        0 ->
            Perms = ecf_thread:perms(Thread),
            case ecf_perms:get_perm(Perms, view_thread) of
                undefined -> [];
                Perm ->
                    List = ecf_perms:allow(Perm),
                    Users = pm_user_list(List),
                    users(Users)
            end;
        _ ->
            []
    end.

pm_user_list(List) ->
    pm_user_list(List, []).

pm_user_list([], Res) ->
    lists:reverse(Res);
pm_user_list([{user, Id}|T], Acc) ->
    pm_user_list(T, [Id|Acc]);
pm_user_list([_H|T], Acc) ->
    pm_user_list(T, Acc).

post_list(Posts) ->
    [post(X) || X <- Posts].

post(Post) ->
    Id = ecf_post:id(Post),
    PosterId = ecf_post:poster(Post),
    Poster = get_user(PosterId),
    Gravatar = gravatar(Poster),
    Time = iso8601:format(ecf_post:time(Post)),
    Text = ecf_post:text(Post),
    [{id, integer_to_binary(Id)},
     {gravatar, Gravatar},
     {poster, user(Poster)},
     {time, Time},
     {text, binary_to_list(Text)}] ++ edited(ecf_post:edited(Post)).

edited(undefined) ->
    [];
edited({Id, Time}) ->
    [{editor, user(Id)}, {edited, iso8601:format(Time)}].

status_desc(400) ->
    "Bad Request";
status_desc(401) ->
    "Unauthorized";
status_desc(403) ->
    "Forbidden";
status_desc(404) ->
    "Not Found";
status_desc(405) ->
    "Bad Method";
status_desc(429) ->
    "Too Many Requests".


% simple memoization using process dict
get_user(Id) ->
    case get({ecf_user, Id}) of
        undefined ->
            U = ecf_user:get_user(Id),
            put({ecf_user, Id}, U),
            U;
        User ->
            User
    end.

-spec get_group(ecf_group:id()) -> ecf_group:group().
get_group(Id) ->
    case get({ecf_group, Id}) of
        undefined ->
            G = ecf_group:get_group(Id),
            put({ecf_group, Id}, G),
            G;
        User ->
            User
    end.

-spec gravatar(ecf_user:user()) -> iodata().
gravatar(User) ->
    Email = string:lowercase(ecf_user:email(User)),
    Hash = erlang:md5(Email),
    Hex = [[io_lib:format("~2.16.0b", [X]) || <<X:8>> <= Hash]],
    [?GRAVATAR_URL, Hex, ?GRAVATAR_OPTIONS].

