module DeferredRequests exposing
  ( DeferredRequest
  , DeferredStatus (..)
  , Tomsg
  , Model
  , Msg
  , init
  , update
  , subscribeCmd
  , maybeSubscribeCmd
  , wsSubscriptions
  , requests
  , subscriptions
  )


import Json.Decode as JD
import Dict exposing (Dict)
import Http
import WebSocket
import Task


type alias DeferredRequest =
  { status: DeferredStatus
  , time: String
  }


type DeferredStatus
  = OK
  | ERR
  | EXE


type alias Tomsg msg = Msg msg -> msg


type alias Subscription msg = (Result Http.Error JD.Value) -> msg


type alias Config =
  { deferredResultBaseUri: String
  , wsNotificationUri: String
  }

type Model msg = Model (Dict String DeferredRequest) (Dict String (Subscription msg)) Config


type Msg msg
  = UpdateMsg String
  | SubscribeMsg String (Subscription msg)


init: String -> String -> Model msg
init deferredResultBaseUri wsNotificationUri =
  Model Dict.empty Dict.empty <| Config deferredResultBaseUri wsNotificationUri


requests: Model msg -> Dict String DeferredRequest
requests (Model r _ _) = r


subscriptions: Model msg -> List String
subscriptions (Model _ s _) = Dict.keys s


subscribeCmd: Tomsg msg -> Subscription msg -> String -> Cmd msg
subscribeCmd toMsg subscription deferredRequestId =
  Task.perform toMsg <| Task.succeed <| SubscribeMsg deferredRequestId subscription


maybeSubscribeCmd: Tomsg msg -> Subscription msg -> String -> Maybe (Cmd msg)
maybeSubscribeCmd toMsg subscription deferredResponse =
  let
    decoder = JD.field "deferred" JD.string
  in
    (Result.toMaybe <| JD.decodeString decoder deferredResponse) |>
    (Maybe.map <| subscribeCmd toMsg subscription)


update: Tomsg msg -> Msg msg -> Model msg -> ( Model msg, Cmd msg )
update toMsg msg (Model requests subs conf) =
  let
    same = Model requests subs conf

    notificationsDecoder =
      let
        statusMap =
          Dict.fromList
          [ ("OK", (JD.succeed OK))
          , ("ERR", (JD.succeed ERR))
          , ("EXE", (JD.succeed EXE))
          ]

        innerDecoder =
          JD.map2
            (,)
            (JD.field "status"
              (JD.string |>
                JD.andThen
                  (\s -> Maybe.withDefault (JD.fail s) (Dict.get s statusMap))
              )
            )
            (JD.field "time" JD.string)
      in
        JD.keyValuePairs innerDecoder |>
        JD.andThen
          (\l ->
            case l of
              (id, (status, time)) :: [] ->
                JD.succeed <| (id, DeferredRequest status time)

              x -> JD.fail (toString x)
          )

    cmd id toSubMsg =
      Http.send toSubMsg <|
        Http.get (conf.deferredResultBaseUri ++ "/" ++ id) JD.value

    processNotification id req =
      Maybe.map
        (cmd id)
        (if req.status == EXE then Nothing else Dict.get id subs) |> -- get subscription if request is completed
      Maybe.map
        ((,) <| Model requests (Dict.remove id subs) conf) |>  -- remove subscription, set deferred result cmd
      Maybe.withDefault
        ( Model (Dict.insert id req requests) subs conf, Cmd.none ) -- insert notification

    processSubscription id toSubMsg =
      Dict.get id requests |> -- get request
      Maybe.andThen
        (\req -> if req.status == EXE then Nothing else Just (id, toSubMsg)) |>  -- check if request is completed
      Maybe.map
        (uncurry cmd) |> -- get deferred result cmd
      Maybe.map
        ((,) <| Model (Dict.remove id requests) subs conf) |> -- remove request, set deferred result cmd
      Maybe.withDefault
        ( Model requests (Dict.insert id toSubMsg subs) conf, Cmd.none ) -- insert subscription

  in
    case msg of
      UpdateMsg json ->
        Result.toMaybe
          (JD.decodeString notificationsDecoder json) |>
        Maybe.map
          (uncurry processNotification) |>
        Maybe.withDefault ( same, Cmd.none )

      SubscribeMsg id toSubMsg ->
        processSubscription id toSubMsg


wsSubscriptions : Tomsg msg -> Model msg -> Sub msg
wsSubscriptions toMsg (Model _ _ { wsNotificationUri }) =
  Sub.batch
    [ WebSocket.listen wsNotificationUri (toMsg << UpdateMsg)
    , WebSocket.keepAlive wsNotificationUri
    ]
