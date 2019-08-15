module Main exposing (Model, Msg(..), init, main, update, view)

import Browser
import Browser.Navigation as Nav
import Game
import Html exposing (Html, a, button, div, form, h1, h2, h3, img, input, p, span, text)
import Html.Attributes as Attr
import Html.Events exposing (onClick, onInput, onSubmit)
import Http
import Loading exposing (LoaderType(..), defaultConfig)
import Url
import Url.Builder as UrlBuilder
import Url.Parser as Parser exposing ((</>), Parser, map, oneOf, string, top)
import Url.Parser.Query as Query



---- MODEL ----


type alias Model =
    { key : Nav.Key
    , playerId : String
    , page : Page
    }


type Page
    = NotFound
    | Home String
    | GameLoading String
    | GameInProgress String Game.Game Game.Team


init : String -> Url.Url -> Nav.Key -> ( Model, Cmd Msg )
init playerId url key =
    stepUrl url { key = key, playerId = playerId, page = Home "" }



---- UPDATE ----


type Msg
    = NoOp
    | LinkClicked Browser.UrlRequest
    | UrlChanged Url.Url
    | IdChanged String
    | SubmitNewGame
    | PickTeam Game.Team
    | PickWord Game.Cell
    | GotGame (Result Http.Error Game.Game)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        LinkClicked urlRequest ->
            case urlRequest of
                Browser.Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                Browser.External href ->
                    ( model
                    , Nav.load href
                    )

        UrlChanged url ->
            stepUrl url model

        IdChanged id ->
            case model.page of
                Home _ ->
                    ( { model | page = Home id }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        SubmitNewGame ->
            case model.page of
                Home id ->
                    ( model, Nav.pushUrl model.key (UrlBuilder.relative [ id ] []) )

                _ ->
                    ( model, Cmd.none )

        GotGame (Ok game) ->
            case model.page of
                GameInProgress id _ t ->
                    ( { model | page = GameInProgress id game t }, Cmd.none )

                GameLoading id ->
                    ( { model | page = GameInProgress id game (Game.teamOf game model.playerId) }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        PickTeam team ->
            case model.page of
                GameInProgress id game _ ->
                    ( { model | page = GameInProgress id game team }, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        PickWord cell ->
            case model.page of
                GameInProgress id game team ->
                    if team == Game.NoTeam then
                        ( model, Cmd.none )

                    else
                        ( model, Game.guess id model.playerId cell team GotGame )

                _ ->
                    ( model, Cmd.none )

        -- TODO: display an error message
        GotGame (Err e) ->
            ( model, Cmd.none )

        NoOp ->
            ( model, Cmd.none )


stepUrl : Url.Url -> Model -> ( Model, Cmd Msg )
stepUrl url model =
    case Maybe.withDefault NullRoute (Parser.parse route url) of
        NullRoute ->
            ( { model | page = NotFound }, Cmd.none )

        Index ->
            ( { model | page = Home "" }, Cmd.none )

        GameView id ->
            stepGameView model id


stepGameView : Model -> String -> ( Model, Cmd Msg )
stepGameView model id =
    ( { model | page = GameLoading id }, Game.maybeMakeGame id GotGame )


type Route
    = NullRoute
    | Index
    | GameView String


route : Parser (Route -> a) a
route =
    oneOf
        [ map Index top
        , map GameView string
        ]



---- VIEW ----


view : Model -> Browser.Document Msg
view model =
    case model.page of
        NotFound ->
            viewNotFound

        Home id ->
            viewHome id

        GameLoading id ->
            { title = "Codenames Green"
            , body = viewGameLoading id
            }

        GameInProgress _ game team ->
            viewGameInProgress model.playerId game team


viewNotFound : Browser.Document Msg
viewNotFound =
    { title = "Codenames Green | Page not found"
    , body =
        [ viewHeader
        , div [ Attr.id "not-found" ]
            [ h2 [] [ text "Page not found" ]
            , p []
                [ text "That page doesn't exist. "
                , a [ Attr.href "/" ] [ text "Go to the homepage" ]
                ]
            ]
        ]
    }


viewGameInProgress : String -> Game.Game -> Game.Team -> Browser.Document Msg
viewGameInProgress playerId g team =
    { title = "Codenames Green"
    , body =
        [ viewHeader
        , div [ Attr.id "game" ]
            [ div [ Attr.id "board" ]
                (List.map
                    (\c -> viewCell c team)
                    (Game.cells g)
                )
            , div [ Attr.id "sidebar" ] (viewSidebar playerId g team)
            ]
        ]
    }


viewCell : Game.Cell -> Game.Team -> Html Msg
viewCell cell team =
    let
        exposedGreen =
            cell.a == ( True, "g" ) || cell.b == ( True, "g" )

        exposedBlack =
            cell.a == ( True, "b" ) || cell.b == ( True, "b" )

        pickable =
            case team of
                Game.A ->
                    not (Tuple.first cell.b) && not exposedGreen && not exposedBlack

                Game.B ->
                    not (Tuple.first cell.a) && not exposedGreen && not exposedBlack

                Game.NoTeam ->
                    False
    in
    div
        [ Attr.classList
            [ ( "cell", True )
            , ( "green", exposedGreen )
            , ( "black", exposedBlack )
            , ( "pickable", pickable )
            ]
        , onClick
            (if pickable then
                PickWord cell

             else
                NoOp
            )
        ]
        [ text cell.word ]


viewSidebar : String -> Game.Game -> Game.Team -> List (Html Msg)
viewSidebar playerId g team =
    if team == Game.NoTeam then
        [ viewJoinATeam (Game.playersOnTeam g Game.A) (Game.playersOnTeam g Game.B) ]

    else
        viewTeamSidebar playerId g team


viewTeamSidebar : String -> Game.Game -> Game.Team -> List (Html Msg)
viewTeamSidebar playerId g team =
    [ div [ Attr.id "key-card" ]
        (List.map
            (\c ->
                div
                    [ Attr.class "cell"
                    , Attr.class
                        (case c of
                            "g" ->
                                "green"

                            "b" ->
                                "black"

                            "t" ->
                                "tan"

                            _ ->
                                "unknown"
                        )
                    ]
                    []
            )
            (if team == Game.A then
                g.oneLayout

             else
                g.twoLayout
            )
        )
    ]


viewJoinATeam : Int -> Int -> Html Msg
viewJoinATeam a b =
    div [ Attr.id "join-a-team" ]
        [ h3 [] [ text "Pick a side" ]
        , p [] [ text "Pick a side to start playing. Each side has a different key card." ]
        , div [ Attr.class "buttons" ]
            [ button [ onClick (PickTeam Game.A) ]
                [ span [ Attr.class "call-to-action" ] [ text "A" ]
                , span [ Attr.class "details" ] [ text "(", text (String.fromInt a), text " players)" ]
                ]
            , button [ onClick (PickTeam Game.B) ]
                [ span [ Attr.class "call-to-action" ] [ text "B" ]
                , span [ Attr.class "details" ] [ text "(", text (String.fromInt b), text " players)" ]
                ]
            ]
        ]


viewGameLoading : String -> List (Html Msg)
viewGameLoading id =
    [ viewHeader
    , div [ Attr.id "game-loading" ]
        [ Loading.render Circle { defaultConfig | size = 100, color = "#b7ec8a" } Loading.On
        ]
    ]


viewHome : String -> Browser.Document Msg
viewHome id =
    { title = "Codenames Green"
    , body =
        [ div [ Attr.id "home" ]
            [ h1 [] [ text "Codenames Green" ]
            , p [] [ text "Play cooperative Codenames online across multiple devices on a shared board. To create a new game or join an existing game, enter a game identifier and click 'GO'." ]
            , form
                [ Attr.id "new-game"
                , onSubmit SubmitNewGame
                ]
                [ input
                    [ Attr.id "game-id"
                    , Attr.name "game-id"
                    , Attr.value id
                    , onInput IdChanged
                    ]
                    []
                , button [] [ text "Go" ]
                ]
            ]
        ]
    }


viewHeader : Html Msg
viewHeader =
    div [ Attr.id "header" ] [ a [ Attr.href "/" ] [ h1 [] [ text "Codenames Green" ] ] ]



---- PROGRAM ----


main : Program String Model Msg
main =
    Browser.application
        { view = view
        , init = init
        , update = update
        , subscriptions = always Sub.none
        , onUrlRequest = LinkClicked
        , onUrlChange = UrlChanged
        }