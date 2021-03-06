module Update exposing (update)

import Array exposing (Array)
import Commands as C
import Messages exposing (..)
import Model exposing (Model, initialModel)
import Models.Exercises exposing (ExerciseId, Exercise, initialExercise)
import Models.Routines exposing (RoutineId, initialRoutine)
import Models.Sections exposing (initialSectionForm)
import Navigation
import RoutineForm exposing (updateRoutineForm)
import Routing exposing (Route(..), routeFromResult, reverse)
import SavingStatus
import Utils exposing (findById, replaceById, updateByIndex, removeByIndex)


{-| Update the Model's `route` when the URL changes.
-}
urlUpdate : Route -> Model -> ( Model, Cmd Msg )
urlUpdate route model =
    let
        {- Initialize Forms on Add/Edit Pages -}
        updatedModel =
            case route of
                ExerciseAddRoute ->
                    { model | exerciseForm = initialExercise }

                ExerciseEditRoute id ->
                    setExerciseForm id model

                RoutineAddRoute ->
                    { model | routineForm = initialRoutine }

                RoutineEditRoute id ->
                    initializeRoutineForm id model

                _ ->
                    model
    in
        ( { updatedModel | route = route }, C.fetchForRoute route )


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        UrlUpdate route ->
            urlUpdate route model

        NavigateTo route ->
            ( model, Navigation.newUrl <| reverse route )

        DeleteExerciseClicked exerciseId ->
            findById exerciseId model.exercises
                |> Maybe.map (C.deleteExercise << .id)
                |> Maybe.withDefault Cmd.none
                |> \cmd -> ( model, cmd )

        ExerciseFormChange subMsg ->
            ( { model | exerciseForm = updateExerciseForm subMsg model }, Cmd.none )

        SubmitExerciseForm ->
            if model.exerciseForm.id == 0 then
                ( model, C.createExercise model.exerciseForm )
            else
                ( model, C.updateExercise model.exerciseForm )

        CancelExerciseForm ->
            if model.exerciseForm.id == 0 then
                ( model, Navigation.newUrl <| reverse ExercisesRoute )
            else
                ( model, Navigation.newUrl <| reverse <| ExerciseRoute model.exerciseForm.id )

        FetchExercises (Ok newExercises) ->
            ( { model | exercises = List.sortBy .name newExercises }, Cmd.none )

        FetchExercises (Err _) ->
            ( model, Cmd.none )

        FetchExercise (Ok newExercise) ->
            let
                updatedModel =
                    { model | exercises = newExercise :: model.exercises }
            in
                case model.route of
                    ExerciseEditRoute id ->
                        ( setExerciseForm id updatedModel, Cmd.none )

                    _ ->
                        ( updatedModel, Cmd.none )

        FetchExercise (Err _) ->
            ( model, Cmd.none )

        CreateExercise (Ok newExercise) ->
            ( { model | exercises = newExercise :: model.exercises }
            , Navigation.newUrl <| reverse <| ExerciseRoute newExercise.id
            )

        CreateExercise (Err _) ->
            ( model, Cmd.none )

        DeleteExercise (Ok exerciseId) ->
            ( { model | exercises = List.filter (\x -> x.id /= exerciseId) model.exercises }
            , Navigation.newUrl <| reverse ExercisesRoute
            )

        DeleteExercise (Err _) ->
            ( model, Cmd.none )

        DeleteRoutineClicked id ->
            ( model, C.deleteRoutine id )

        RoutineFormChange subMsg ->
            ( updateRoutineForm subMsg model, Cmd.none )

        SubmitAddRoutineForm ->
            ( model, C.createRoutine model.routineForm )

        CancelAddRoutineForm ->
            ( model, Navigation.newUrl <| reverse <| RoutinesRoute )

        SaveSectionClicked index ->
            ( model
            , Array.get index model.sectionForms
                |> Maybe.map
                    (.section >> C.createOrUpdate (C.createSection index) (C.updateSection index))
                |> Maybe.withDefault Cmd.none
            )

        DeleteSectionClicked sectionIndex id ->
            ( model, C.deleteSection sectionIndex id )

        SaveSectionExerciseClicked sectionIndex exerciseIndex ->
            ( model
            , Array.get sectionIndex model.sectionForms
                |> Maybe.andThen
                    (.exercises
                        >> Array.get exerciseIndex
                        >> Maybe.map
                            (C.createOrUpdate
                                (C.createSectionExercise sectionIndex exerciseIndex)
                                (C.updateSectionExercise sectionIndex exerciseIndex)
                            )
                    )
                |> Maybe.withDefault Cmd.none
            )

        DeleteSectionExerciseClicked sectionIndex exerciseIndex id ->
            ( model, C.deleteSectionExercise sectionIndex exerciseIndex id )

        SubmitEditRoutineForm ->
            ( model, C.updateRoutine model.routineForm )

        {- Reset the RoutineForm & Redirect to the Routine's Details Page -}
        CancelEditRoutineForm ->
            ( initializeRoutineForm model.routineForm.id model
            , Navigation.newUrl <| reverse <| RoutineRoute model.routineForm.id
            )

        FetchRoutines (Ok newRoutines) ->
            ( { model | routines = newRoutines }, Cmd.none )

        FetchRoutines (Err _) ->
            ( model, Cmd.none )

        FetchRoutine (Ok newRoutine) ->
            let
                updatedModel =
                    { model | routines = newRoutine :: model.routines }
            in
                ( reinitializeRoutineForm updatedModel, Cmd.none )

        FetchRoutine (Err _) ->
            ( model, Cmd.none )

        CreateRoutine (Ok newRoutine) ->
            ( { model | routines = newRoutine :: model.routines }
            , Navigation.newUrl <| reverse <| RoutineEditRoute newRoutine.id
            )

        CreateRoutine (Err _) ->
            ( model, Cmd.none )

        UpdateRoutine (Ok newRoutine) ->
            ( { model
                | routines = replaceById newRoutine model.routines
                , routineForm = newRoutine
                , savingStatus = SavingStatus.start model.savingStatus
              }
            , C.createOrUpdateArray .section C.createSection C.updateSection model.sectionForms
            )

        UpdateRoutine (Err _) ->
            ( model, Cmd.none )

        {- Remove the Routine from the Model -}
        DeleteRoutine (Ok routineId) ->
            ( { model | routines = List.filter (\x -> x.id /= routineId) model.routines }
            , Navigation.newUrl <| reverse RoutinesRoute
            )

        DeleteRoutine (Err _) ->
            ( model, Cmd.none )

        {- Replace the Sections in the Model -}
        FetchSections (Ok newSections) ->
            let
                updatedModel =
                    { model | sections = List.sortBy .order newSections }
            in
                ( reinitializeRoutineForm updatedModel, Cmd.none )

        FetchSections (Err _) ->
            ( model, Cmd.none )

        {- Add the Section to the Model & Update the SectionForm & SavingStatus -}
        CreateSection index (Ok newSection) ->
            let
                updatedForms =
                    updateByIndex index
                        (\form ->
                            { form
                                | section = newSection
                                , exercises = Array.map updateSectionIds form.exercises
                            }
                        )
                        model.sectionForms

                updateSectionIds sectionExercise =
                    { sectionExercise | section = newSection.id }
            in
                enqueueSavingSectionExercises index
                    { model
                        | sectionForms = updatedForms
                        , sections = newSection :: model.sections
                    }

        CreateSection _ (Err _) ->
            ( model, Cmd.none )

        {- Update the Section, SectionForm, & SavingStatus -}
        UpdateSection index (Ok newSection) ->
            let
                updatedForms =
                    updateByIndex index
                        (\form -> { form | section = newSection })
                        model.sectionForms
            in
                enqueueSavingSectionExercises index
                    { model
                        | sectionForms = updatedForms
                        , sections = replaceById newSection model.sections
                    }

        UpdateSection _ (Err _) ->
            ( model, Cmd.none )

        {- Remove the SectionForm and the Section from the Model -}
        DeleteSection index (Ok sectionId) ->
            ( { model
                | sectionForms = removeByIndex index model.sectionForms
                , sections = List.filter (\x -> x.id /= sectionId) model.sections
              }
            , Cmd.none
            )

        DeleteSection _ (Err _) ->
            ( model, Cmd.none )

        {- Replace all the SectionExercises stored in the Model -}
        FetchSectionExercises (Ok newSectionExercises) ->
            ( reinitializeRoutineForm
                { model | sectionExercises = List.sortBy .order newSectionExercises }
            , Cmd.none
            )

        FetchSectionExercises (Err _) ->
            ( model, Cmd.none )

        {- Replace the SectionExercise in it's SectionForm & add it to the Model -}
        CreateSectionExercise sectionIndex exerciseIndex (Ok newSectionExercise) ->
            let
                updateSection sectionForm =
                    { sectionForm
                        | exercises =
                            Array.set exerciseIndex newSectionExercise sectionForm.exercises
                    }
            in
                finishSavingSectionExercise
                    { model
                        | sectionForms = updateByIndex sectionIndex updateSection model.sectionForms
                        , sectionExercises = newSectionExercise :: model.sectionExercises
                    }

        CreateSectionExercise _ _ (Err _) ->
            ( model, Cmd.none )

        {- Replace the SectionExercise in the Model & it's SectionForm -}
        UpdateSectionExercise sectionIndex exerciseIndex (Ok newSectionExercise) ->
            let
                updateSection sectionForm =
                    { sectionForm
                        | exercises =
                            Array.set exerciseIndex newSectionExercise sectionForm.exercises
                    }
            in
                finishSavingSectionExercise
                    { model
                        | sectionForms = updateByIndex sectionIndex updateSection model.sectionForms
                        , sectionExercises = replaceById newSectionExercise model.sectionExercises
                    }

        UpdateSectionExercise _ _ (Err _) ->
            ( model, Cmd.none )

        {- Remove the SectionExercise from the Model & SectionForm -}
        DeleteSectionExercise sectionIndex exerciseIndex (Ok sectionExerciseId) ->
            let
                updateSection sectionForm =
                    { sectionForm
                        | exercises = removeByIndex exerciseIndex sectionForm.exercises
                    }
            in
                ( { model
                    | sectionForms = updateByIndex sectionIndex updateSection model.sectionForms
                    , sectionExercises = List.filter (\x -> x.id /= sectionExerciseId) model.sectionExercises
                  }
                , Cmd.none
                )

        DeleteSectionExercise _ _ (Err _) ->
            ( model, Cmd.none )


{-| Set the Exercise Form to the Exercise with the specified Id.
-}
setExerciseForm : ExerciseId -> Model -> Model
setExerciseForm id model =
    let
        newForm =
            findById id model.exercises
                |> Maybe.withDefault initialExercise
    in
        { model | exerciseForm = newForm }


{-| Update the Exercise Form when a field has changed.
-}
updateExerciseForm : ExerciseFormMessage -> Model -> Exercise
updateExerciseForm msg ({ exerciseForm } as model) =
    case msg of
        ExerciseNameChange newName ->
            { exerciseForm | name = newName }

        DescriptionChange newDescription ->
            { exerciseForm | description = newDescription }

        IsHoldChange newHold ->
            { exerciseForm | isHold = newHold }

        YoutubeChange newYoutube ->
            { exerciseForm | youtubeIds = newYoutube }

        AmazonChange newAmazon ->
            { exerciseForm | amazonIds = newAmazon }


{-| Set the Routine Form to the Routine with the specified id.
-}
initializeRoutineForm : RoutineId -> Model -> Model
initializeRoutineForm id model =
    let
        newForm =
            findById id model.routines
                |> Maybe.withDefault initialRoutine

        sections =
            List.filter (\s -> s.routine == id) model.sections

        exercises sectionId =
            List.filter (\sx -> sx.section == sectionId) model.sectionExercises
                |> Array.fromList

        sectionForms =
            if List.length sections > 0 then
                sections
                    |> List.map (\s -> { section = s, exercises = exercises s.id })
                    |> Array.fromList
            else
                Array.fromList [ initialSectionForm id ]
    in
        { model
            | routineForm = newForm
            , sectionForms = sectionForms
        }


{-| Reinitialize the RoutineForm if currently at the RoutineEditRoute.
-}
reinitializeRoutineForm : Model -> Model
reinitializeRoutineForm model =
    case model.route of
        RoutineEditRoute id ->
            initializeRoutineForm id model

        _ ->
            model


{-| Enqueue the saving of a SectionForm's Exercises.
-}
enqueueSavingSectionExercises : Int -> Model -> ( Model, Cmd Msg )
enqueueSavingSectionExercises index model =
    let
        saveSectionExercises { exercises } =
            C.createOrUpdateArray identity
                (C.createSectionExercise index)
                (C.updateSectionExercise index)
                exercises
    in
        ( { model
            | savingStatus =
                SavingStatus.enqueue model.savingStatus <|
                    (Array.get index model.sectionForms
                        |> Maybe.map (\{ exercises } -> exercises)
                        |> Maybe.withDefault Array.empty
                        |> Array.length
                    )
          }
        , Array.get index model.sectionForms
            |> Maybe.map saveSectionExercises
            |> Maybe.withDefault Cmd.none
        )


{-| Mark a SectionExercise Form as saved & redirect if finished saving.
-}
finishSavingSectionExercise : Model -> ( Model, Cmd Msg )
finishSavingSectionExercise model =
    let
        updatedSavingStatus =
            SavingStatus.finishOne model.savingStatus

        redirectCmd =
            Navigation.newUrl (reverse <| RoutineRoute model.routineForm.id)
    in
        if SavingStatus.isFinished updatedSavingStatus then
            ( { model | savingStatus = SavingStatus.initial }, redirectCmd )
        else
            ( { model | savingStatus = updatedSavingStatus }, Cmd.none )
