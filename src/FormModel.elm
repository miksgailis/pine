module FormModel exposing
  ( Model, Msg, Tomsg
  , init, toModelMsg
  , createMsg, saveMsg, fetchMsg, editMsg, cancelMsg, cancelWithActionMsg
  , deleteMsg, setMsg
  , create, save, fetch, edit, cancel, cancelWithAction, delete, set, map
  , update
  )


import EditModel as EM
import JsonModel as JM
import Ask
import Utils exposing (..)

import Task
import Dict

type alias Model msg =
  { init: () -> EM.JsonEditModel msg
  , form: Maybe (EM.JsonEditModel msg)
  , toMessagemsg: Ask.Tomsg msg
  }


type Msg msg
  = CreateMsg (EM.JsonEditMsg msg)
  | EditMsg JM.JsonValue
  | CancelEditMsg (Maybe msg) Bool
  | SaveMsg (Maybe (JM.JsonValue -> msg)) (EM.JsonEditMsg msg)
  | DeleteMsg (Maybe (JM.JsonValue -> msg)) Int
  | SetMsg JM.JsonValue


type alias Tomsg msg = Msg msg -> msg


init: (() -> EM.JsonEditModel msg) -> Ask.Tomsg msg -> Model msg
init initializer =
  Model initializer Nothing


toModelMsg: Tomsg msg -> (EM.JsonEditMsg msg -> msg)
toModelMsg toMsg =
  toMsg << CreateMsg


createMsg: Tomsg msg -> JM.SearchParams -> (JM.JsonValue -> JM.JsonValue) -> msg
createMsg toMsg searchParams =
  EM.createMsg (toModelMsg toMsg) searchParams


create: Tomsg msg -> JM.SearchParams -> (JM.JsonValue -> JM.JsonValue) -> Cmd msg
create toMsg searchParams =
  domsg << createMsg toMsg searchParams


saveMsg: Tomsg msg -> Maybe (JM.JsonValue -> msg) -> msg
saveMsg toMsg maybeSuccessmsg =
  EM.saveMsg (toMsg << SaveMsg maybeSuccessmsg)


save: Tomsg msg -> Maybe (JM.JsonValue -> msg) -> Cmd msg
save toMsg =
  domsg << saveMsg toMsg


fetchMsg: Tomsg msg -> Int -> msg
fetchMsg toMsg id =
  editMsg toMsg <| JM.jsonEdit "id" (JM.JsNumber <| toFloat id) JM.jsonEmptyObj


fetch: Tomsg msg -> Int -> Cmd msg
fetch toMsg =
  domsg << fetchMsg toMsg


editMsg: Tomsg msg -> JM.JsonValue -> msg
editMsg toMsg =
  toMsg << EditMsg


edit: Tomsg msg -> JM.JsonValue -> Cmd msg
edit toMsg =
  domsg << editMsg toMsg


cancelMsg: Tomsg msg -> Bool -> msg
cancelMsg toMsg =
  toMsg << CancelEditMsg Nothing


cancel: Tomsg msg -> Bool -> Cmd msg
cancel toMsg =
  domsg << cancelMsg toMsg


cancelWithActionMsg: Tomsg msg -> msg -> Bool -> msg
cancelWithActionMsg toMsg msg =
  toMsg << CancelEditMsg (Just msg)


cancelWithAction: Tomsg msg -> msg -> Bool -> Cmd msg
cancelWithAction toMsg msg =
  domsg << cancelWithActionMsg toMsg msg


deleteMsg: Tomsg msg -> Maybe (JM.JsonValue -> msg) -> Int -> msg
deleteMsg toMsg maybeSuccessmsg =
  toMsg << DeleteMsg maybeSuccessmsg


delete: Tomsg msg -> Maybe (JM.JsonValue -> msg) -> Int -> Cmd msg
delete toMsg maybeSuccessmsg =
  domsg << deleteMsg toMsg maybeSuccessmsg


setMsg: Tomsg msg -> JM.JsonValue -> msg
setMsg toMsg =
  toMsg << SetMsg


set: Tomsg msg -> JM.JsonValue -> Cmd msg
set toMsg =
  domsg << setMsg toMsg


map: (JM.JsonValue -> JM.JsonValue) -> Model msg -> Model msg
map mapper model =
  model.form |>
  Maybe.map (\f -> { f | model = JM.map mapper f.model }) |>
  Maybe.map (\f -> { model | form = Just f}) |>
  Maybe.withDefault model


update: Tomsg msg -> Msg msg -> Model msg -> (Model msg, Cmd msg)
update toMsg msg ({ form, toMessagemsg } as model) =
  case msg of
    CreateMsg data ->
      form |>
      Utils.orElse (Just <| model.init ()) |>
      Maybe.map (EM.update (toMsg << CreateMsg) data) |>
      Maybe.map
        (Tuple.mapFirst (\m -> { model | form = Just m})) |>
      Maybe.withDefault ( model, Cmd.none )

    EditMsg data ->
      ( model
      , JM.jsonInt "id" data |>
        Maybe.map (EM.fetch (toMsg << CreateMsg)) |>
        Maybe.withDefault Cmd.none
      )

    CancelEditMsg maybeMsg ask ->
      if ask && (model.form |> Maybe.map .isDirty |> Maybe.withDefault False) then
        ( model
        , Ask.ask
            toMessagemsg
            "Vai atcelt datu labošanu?"
            (cancel toMsg False)
            Nothing
        )
      else
        ( { model | form = Nothing }
        , maybeMsg |> Maybe.map (domsg) |> Maybe.withDefault Cmd.none
        )

    SaveMsg maybeSuccessmsg data ->
      form |>
      Maybe.map (EM.update (toMsg << SaveMsg maybeSuccessmsg) data) |>
      Maybe.map (Tuple.mapFirst (\m -> { model | form = Just m})) |>
      Maybe.withDefault ( model, Cmd.none ) |>
      (\(newmod, cmd) ->
        if cmd == Cmd.none then
          ( { model | form = Nothing }
          , Maybe.map2
              (\f m -> domsg <| m <| JM.data f.model)
              newmod.form
              maybeSuccessmsg |>
            Maybe.withDefault Cmd.none
          )
        else ( newmod, cmd )
      )

    DeleteMsg maybeSuccessmsg id ->
      Tuple.pair
        model <|
        Ask.ask
          toMessagemsg
          "Vai dzēst ierakstu?"
          (EM.delete (toMsg << SaveMsg maybeSuccessmsg) id)
          Nothing

    SetMsg data ->
      ( model, EM.set (toMsg << CreateMsg) <| always data )
