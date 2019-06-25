module ListModel exposing
  ( Model (..), Config, Msg, Tomsg
  , init, config, toParamsMsg, toListMsg
  , loadMsg, loadMoreMsg, sortMsg, selectMsg, load, loadMore, sort, select
  , update, subs
  )


import JsonModel as JM
import EditModel as EM
import ViewMetadata as VM
import ScrollEvents as SE
import Utils
import Ask

import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Task
import Browser.Navigation as Nav


type Model msg =
  Model
    { searchParams: EM.JsonEditModel msg
    , list: JM.JsonListModel msg
    , stickyPos: Maybe SE.StickyElPos
    , sortCol: Maybe (String, Bool)
    , changeUrl: Bool
    , addHistory: Bool
    }


type alias Config msg =
  { colFilter: VM.Field -> Bool
  , colOrder: Maybe String
  , rowAttrs: JM.JsonValue -> List (Attribute msg)
  , headers: Dict String (String -> Html msg)
  , cells: Dict String (JM.JsonValue -> Html msg)
  , tableAttrs: List (Attribute msg)
  , selectedMsg: Maybe (Bool -> JM.JsonValue -> msg)
  , multiSelect: Bool
  , loadMoreElId: Maybe String
  , stickId: Maybe String
  }


type Msg msg
  = ParamsMsg (EM.JsonEditMsg msg)
  | ListMsg (JM.JsonListMsg msg)
  | LoadMsg
  | LoadMoreMsg -- load more element visibility subscription message
  | ScrollEventsMsg (SE.Msg msg)
  | StickyPosMsg (Maybe SE.StickyElPos)
  | SortMsg String
  | SelectMsg (Bool -> JM.JsonValue -> msg) Bool JM.JsonValue
  | BrowserKeyMsg Nav.Key


type alias Tomsg msg = Msg msg -> msg


init: Tomsg msg -> EM.JsonEditModel msg -> JM.JsonListModel msg -> Maybe JM.SearchParams -> (Model msg, Cmd msg)
init toMsg searchPars l initPars =
  ( Model
      { searchParams = searchPars
      , list = l
      , stickyPos = Nothing
      , sortCol =
          initPars |>
          Maybe.andThen (Utils.find (\(n, _) -> n == "sort")) |>
          Maybe.map Tuple.second |>
          Maybe.map
            (\c ->
              if String.startsWith "~" c then (String.dropLeft 1 c, False) else (c, True)
            )
      , changeUrl = True
      , addHistory = True
      }
  , initPars |>
    Maybe.map
      (\pars ->
        Cmd.batch
          [ JM.fetchFromStart (toMsg << ListMsg) pars -- fetch list data
          , pars |>
            List.map (Tuple.mapSecond JM.JsString) |>
            (\vals -> EM.set (toMsg << ParamsMsg) (\_ -> JM.JsObject <| Dict.fromList vals)) -- set search form values
          ]
      ) |>
    Maybe.withDefault (EM.set (toMsg << ParamsMsg) identity) -- initialize query form metadata
  )


config: Config msg
config =
  Config (\_ -> True) Nothing (\_ -> []) Dict.empty Dict.empty [] Nothing False Nothing Nothing


toParamsMsg: Tomsg msg -> (EM.JsonEditMsg msg -> msg)
toParamsMsg toMsg =
  toMsg << ParamsMsg


toListMsg: Tomsg msg -> (JM.JsonListMsg msg -> msg)
toListMsg toMsg =
  toMsg << ListMsg


loadMsg: Tomsg msg -> msg
loadMsg toMsg =
  toMsg LoadMsg


load: Tomsg msg -> Cmd msg
load toMsg =
  Task.perform identity <| Task.succeed <| loadMsg toMsg


loadMoreMsg: Tomsg msg -> msg
loadMoreMsg toMsg =
  toMsg LoadMoreMsg


loadMore: Tomsg msg -> Cmd msg
loadMore toMsg =
  Task.perform identity <| Task.succeed <| loadMoreMsg toMsg


sortMsg: Tomsg msg -> String -> msg
sortMsg toMsg col =
  toMsg <| SortMsg col


sort: Tomsg msg -> String -> Cmd msg
sort toMsg col =
  Task.perform identity <| Task.succeed <| sortMsg toMsg col


selectMsg: Tomsg msg -> (Bool -> JM.JsonValue -> msg) -> Bool -> JM.JsonValue -> msg
selectMsg toMsg selectAction multiSelect val =
  toMsg <| SelectMsg selectAction multiSelect val


select: Tomsg msg -> (Bool -> JM.JsonValue -> msg) -> Bool -> JM.JsonValue -> Cmd msg
select toMsg selectAction multiSelect val =
  Task.perform identity <| Task.succeed <| selectMsg toMsg selectAction multiSelect val


update: Tomsg msg -> Msg msg -> Model msg -> (Model msg, Cmd msg)
update toMsg msg (Model ({ searchParams, list, sortCol } as model) as same) =
  let
    searchPars params =
      JM.searchParsFromJson params ++
      ( sortCol |>
        Maybe.map (\(c, o) -> [ ("sort", (if o then "" else "~") ++ c) ]) |>
        Maybe.withDefault []
      )

    changeUrl toMessagemsg =
      Task.perform identity <| Task.succeed <|
        Ask.browserKeymsg toMessagemsg <| toMsg << BrowserKeyMsg
  in
    case msg of
      ParamsMsg data ->
        EM.update (toMsg << ParamsMsg) data searchParams |>
        Tuple.mapFirst (\s -> Model { model | searchParams = s })

      ListMsg data ->
        JM.update (toMsg << ListMsg) data model.list |>
        Tuple.mapFirst (\m -> Model { model | list = m })

      ScrollEventsMsg data ->
        ( Model model, SE.process (toMsg << ScrollEventsMsg) data )

      StickyPosMsg pos ->
        ( Model { model | stickyPos = pos }, Cmd.none )

      SortMsg col ->
        Model
          { model |
            sortCol =
              if sortCol == Nothing then
                Just (col, True)
              else
                model.sortCol |>
                Maybe.andThen
                  (\(c, o) ->
                    if c == col then
                      if not o then Nothing else Just (c, False)
                    else Just (col, True)
                  )
          } |>
        (\m -> ( m, load toMsg ))

      LoadMsg ->
        ( same
        , Cmd.batch
          [ JM.fetchFromStart (toMsg << ListMsg) <| searchPars searchParams.model
          , list |> (\(JM.Model _ c) -> changeUrl c.toMessagemsg)
          ]
        )

      LoadMoreMsg ->
        ( same
        , Cmd.batch
          [ JM.fetch (toMsg << ListMsg) <| searchPars searchParams.model
          , list |> (\(JM.Model _ c) -> changeUrl c.toMessagemsg)
          ]
        )

      SelectMsg selmsg multiSelect data ->
        let
          set isSel d = JM.jsonEdit "is_selected" (JM.JsBool isSel) d
        in
          JM.jsonBool "is_selected" data |>
          Maybe.withDefault False |>
          (\is_selected ->
            ( not is_selected, set (not is_selected) data )
          ) |>
          (\(is_selected, newdata) ->
            ( is_selected
            , newdata
            , JM.data model.list |>
              List.map
                (\rec ->
                  if rec == data then
                    newdata
                  else if not multiSelect && is_selected then
                    set False rec
                  else rec
                )
            )
          ) |>
          (\(is_selected, newdata, newlist) ->
            ( Model { model | list = JM.setData newlist model.list }
            , Task.perform (selmsg is_selected) <| Task.succeed newdata
            )
          )

      BrowserKeyMsg key ->
        ( same
        , (searchPars searchParams.model, list) |>
          (\(sp, (JM.Model d c)) ->
            sp ++
            [ (c.offsetParamName, "0")
            , (c.limitParamName, String.fromInt <| List.length d.data + c.pageSize)
            ] |>
            Utils.httpQuery
          ) |>
          (\q -> if model.addHistory then Nav.pushUrl key q else Nav.replaceUrl key q)
        )


subs: Tomsg msg -> Maybe String -> Maybe String -> Maybe String -> Sub msg
subs toMsg loadMoreElId stickToElId stickId =
  let
    toSEMsg = toMsg << ScrollEventsMsg
  in
    Sub.batch
      [ loadMoreElId |>
        Maybe.map (\id -> SE.visibilitySub toSEMsg id <| toMsg LoadMoreMsg) |>
        Maybe.withDefault Sub.none
      , Maybe.map2
          (\stId id -> SE.stickySub toSEMsg stId id (toMsg << StickyPosMsg))
          stickToElId
          stickId |>
        Maybe.withDefault Sub.none
      ]
