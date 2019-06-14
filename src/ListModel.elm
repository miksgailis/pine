module ListModel exposing (..)


import JsonModel as JM
import EditModel as EM
import ViewMetadata as VM
import ScrollEvents as SE

import Dict exposing (Dict)
import Html exposing (..)
import Html.Attributes exposing (..)
import Task


type Model msg =
  Model
    { searchParams: EM.JsonEditModel msg
    , list: JM.JsonListModel msg
    , stickyPos: Maybe SE.StickyElPos
    , sortCol: Maybe (String, Bool)
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
  | ScrollEventsMsg (SE.Msg msg)
  | StickyPosMsg (Maybe SE.StickyElPos)
  | SortMsg String
  | LoadMoreMsg -- load more element visibility subscription message
  | SelectMsg (Bool -> JM.JsonValue -> msg) Bool JM.JsonValue


type alias Tomsg msg = Msg msg -> msg


init: Tomsg msg -> EM.JsonEditModel msg -> JM.JsonListModel msg -> (Model msg, Cmd msg)
init toMsg searchPars l =
  ( Model
      { searchParams = searchPars
      , list = l
      , stickyPos = Nothing
      , sortCol = Nothing
      }
  , EM.set (toMsg << ParamsMsg) identity -- initialize query form metadata
  )


config: Config msg
config =
  Config (\_ -> True) Nothing (\_ -> []) Dict.empty Dict.empty [] Nothing False Nothing Nothing


params: Model msg -> EM.JsonEditModel msg
params (Model { searchParams }) =
  searchParams


list: Model msg -> JM.JsonListModel msg
list (Model m) =
  m.list


toSearchParamsMsg: Tomsg msg -> (EM.JsonEditMsg msg -> msg)
toSearchParamsMsg toMsg =
  toMsg << ParamsMsg


toListMsg: Tomsg msg -> (JM.JsonListMsg msg -> msg)
toListMsg toMsg =
  toMsg << ListMsg


loadMsg: Tomsg msg -> Model msg -> msg
loadMsg toMsg m =
  JM.fetchFromStartMsg (toMsg << ListMsg) <| searchParamsInternal m


loadMoreMsg: Tomsg msg -> Model msg -> msg
loadMoreMsg toMsg m =
  JM.fetchMsg (toMsg << ListMsg) <| searchParamsInternal m


searchParamsInternal: Model msg -> JM.SearchParams
searchParamsInternal (Model { searchParams, sortCol }) =
  JM.searchParsFromJson searchParams.model ++
  ( sortCol |>
    Maybe.map (\(c, o) -> [ ("sort", (if o then "" else "~") ++ c) ]) |>
    Maybe.withDefault []
  )


update: Tomsg msg -> Msg msg -> Model msg -> (Model msg, Cmd msg)
update toMsg msg (Model ({ searchParams, sortCol } as model) as same) =
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
      (\m -> ( m, Task.perform identity <| Task.succeed <| loadMsg toMsg m ))

    LoadMoreMsg ->
      (same, Task.perform identity <| Task.succeed <| loadMoreMsg toMsg same)

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