%%%-------------------------------------------------------------------
%%% @copyright (C) 2017, 2600Hz, INC
%%% @doc
%%%
%%% @end
%%% @contributors
%%%-------------------------------------------------------------------
-module(kz_services_test).

-include_lib("eunit/include/eunit.hrl").

-define(CAT, <<"phone_numbers">>).
-define(ITEM, <<"did_us">>).

-record(state, {service_plan_jobj :: kzd_service_plan:plan()
               ,services :: kz_services:services()
               ,services_jobj :: kz_json:object()
               ,account_plan :: kzd_service_plan:plan()
               }).

services_test_() ->
    {'foreach'
    ,fun init/0
    ,fun stop/1
    ,[fun services_json_to_record/1
     ,fun services_record_to_json/1
     ,fun service_plan_json_to_plans/1
     ,fun increase_quantities/1
     ]
    }.

init() ->
    lists:foldl(fun init_fold/2
               ,#state{}
               ,[fun read_service_plan/1
                ,fun read_services/1
                ]).

init_fold(F, State) ->
    F(State).

stop(#state{}=_State) ->
    'ok'.

read_service_plan(State) ->
    ServicePlan1 = filename:join([priv_dir(), "example_service_plan_1.json"]),
    JObj = read_json(ServicePlan1),

    State#state{service_plan_jobj=JObj}.

read_services(#state{service_plan_jobj=ServicePlan}=State) ->
    ServicesPath = filename:join([priv_dir(), "example_account_services.json"]),

    JObj = read_json(ServicesPath),

    Services = kz_services:from_service_json(JObj, 'false'),

    Overrides = kzd_services:plan_overrides(JObj, kz_doc:id(ServicePlan)),
    AccountPlan = kzd_service_plan:merge_overrides(ServicePlan, Overrides),

    State#state{services_jobj=JObj
               ,services=Services
               ,account_plan=AccountPlan
               }.

priv_dir() ->
    {'ok', AppDir} = file:get_cwd(),
    filename:join([AppDir, "priv"]).

read_json(Path) ->
    {'ok', JSON} = file:read_file(Path),
    kz_json:decode(JSON).

services_json_to_record(#state{services=Services
                              ,services_jobj=JObj
                              }) ->
    [{"Verify account id is set properly"
     ,?_assertEqual(kz_doc:account_id(JObj)
                   ,kz_services:account_id(Services)
                   )
     }
    ,{"Verify the dirty flag is set properly"
     ,?_assertEqual(kzd_services:is_dirty(JObj)
                   ,kz_services:is_dirty(Services)
                   )
     }
    ,{"Verify the billing id"
     ,?_assertEqual(kzd_services:billing_id(JObj)
                   ,kz_services:get_billing_id(Services)
                   )
     }
     | quantity_checks(Services, JObj)
    ].

services_record_to_json(#state{services=Services}) ->
    JObj = kz_services:to_json(Services),
    [{"Verify account id is set properly"
     ,?_assertEqual(kz_doc:account_id(JObj)
                   ,kz_services:account_id(Services)
                   )
     }
    ,{"Verify the dirty flag is set properly"
     ,?_assertEqual(kzd_services:is_dirty(JObj)
                   ,kz_services:is_dirty(Services)
                   )
     }
    ,{"Verify the billing id"
     ,?_assertEqual(kzd_services:billing_id(JObj)
                   ,kz_services:get_billing_id(Services)
                   )
     }
     | quantity_checks(Services, JObj)
    ].

quantity_checks(Services, JObj) ->
    {Tests, _} = kz_json:foldl(fun category_checks/3
                              ,{[], Services}
                              ,kzd_services:quantities(JObj)
                              ),
    Tests.

category_checks(Category, CategoryJObj, Acc) ->
    kz_json:foldl(fun(K, V, Acc1) ->
                          item_checks(Category, K, V, Acc1)
                  end
                 ,Acc
                 ,CategoryJObj
                 ).

item_checks(Category, Item, Quantity, {Tests, Services}) ->
    {[item_check(Category, Item, Quantity, Services) | Tests]
    ,Services
    }.

item_check(Category, Item, Quantity, Services) ->
    {iolist_to_binary(io_lib:format("Verify ~s.~s is ~p", [Category, Item, Quantity]))
    ,?_assertEqual(Quantity, kz_services:quantity(Category, Item, Services))
    }.

service_plan_json_to_plans(#state{service_plan_jobj=ServicePlan
                                 ,account_plan=AccountPlan
                                 }) ->

    [{"Verify plan from file matches services plan"
     ,?_assertEqual(kz_doc:account_id(ServicePlan)
                   ,kzd_service_plan:account_id(AccountPlan)
                   )
     }
    ,{"Verify cumulative discount rate from service plan"
     ,?_assertEqual(0.5, rate(cumulative_discount(did_us_item(ServicePlan))))
     }
    ,{"Verify cumulative discount rate was overridden"
     ,?_assertEqual(5.0, rate(cumulative_discount(did_us_item(AccountPlan))))
     }
    ].

did_us_item(Plan) ->
    kzd_service_plan:item(Plan, ?CAT, ?ITEM).

cumulative_discount(Item) ->
    kzd_item_plan:cumulative_discount(Item).

rate(JObj) ->
    kz_json:get_float_value(<<"rate">>, JObj).

increase_quantities(#state{account_plan=_AccountPlan
                          ,services=Services
                          }) ->
    ItemQuantity = kz_services:quantity(?CAT, ?ITEM, Services),

    Increment = rand:uniform(10),

    UpdatedServices = kz_services:update(?CAT, ?ITEM, ItemQuantity+Increment, Services),

    UpdatedItemQuantity = kz_services:quantity(?CAT, ?ITEM, UpdatedServices),

    DiffItemQuantity = kz_services:diff_quantity(?CAT, ?ITEM, UpdatedServices),

    [{"Verify base quantity on the services doc"
     ,?_assertEqual(9, ItemQuantity)
     }
    ,{"Verify incrementing the quantity"
     ,?_assertEqual(ItemQuantity+Increment, UpdatedItemQuantity)
     }
    ,{"Verify the diff of the quantity"
     ,?_assertEqual(Increment, DiffItemQuantity)
     }
     | category_quantities(Services, UpdatedServices, Increment)
    ].

category_quantities(CurrentServices, UpdatedServices, Increment) ->
    CategoryQuantity = kz_services:category_quantity(?CAT, CurrentServices),
    UpdatedCategoryQuantity = kz_services:category_quantity(?CAT, UpdatedServices),

    TollFreeQuantity = kz_services:quantity(?CAT, <<"toll_free">>, UpdatedServices),
    DIDUSQuantity = kz_services:quantity(?CAT, ?ITEM, UpdatedServices),

    MinusTollFree = kz_services:category_quantity(?CAT, [<<"toll_free">>], UpdatedServices),
    MinusDIDUS = kz_services:category_quantity(?CAT, [?ITEM], UpdatedServices),

    [{"Verify base category quantities"
     ,?_assertEqual(10, CategoryQuantity)
     }
    ,{"Verify updated category quantities"
     ,?_assertEqual(CategoryQuantity + Increment, UpdatedCategoryQuantity)
     }
    ,{"Verify updated category quantities minus toll_free numbers"
     ,?_assertEqual(MinusTollFree, UpdatedCategoryQuantity-TollFreeQuantity)
     }
    ,{"Verify updated category quantities minus did_us numbers"
     ,?_assertEqual(MinusDIDUS, UpdatedCategoryQuantity-DIDUSQuantity)
     }
    ].
