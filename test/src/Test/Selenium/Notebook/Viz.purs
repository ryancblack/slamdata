{-
Copyright 2015 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module Test.Selenium.Notebook.Viz (test) where

import Prelude

import Control.Monad.Eff.Random (randomInt)
import Control.Monad.Eff.Class (liftEff)
import Data.List (length, List(..), fromList, filter, null, (!!))
import Data.Maybe (isJust, isNothing, Maybe(..), maybe, fromMaybe)
import Data.Maybe.Unsafe (fromJust)
import Data.Traversable (traverse)
import Data.Foldable (foldl)
import Data.Monoid (mempty)
import Data.Function (on)
import qualified Data.Set as S

import Selenium.Types
import Selenium.Monad
import Selenium.ActionSequence hiding (sequence)

import Test.Config
import Test.Selenium.ActionSequence (selectAll, sendDelete, sendEnter)
import Test.Selenium.Monad
import Test.Selenium.Log
import Test.Selenium.Common
import Test.Selenium.Notebook.Getters
import Test.Selenium.Notebook.Contexts
import qualified Test.Selenium.Notebook.Common as C
import qualified Config as SDConfig

import Utils (s2i)
import Utils.Random

checkNextVizCell :: Check Unit
checkNextVizCell = do
  waitNextVizCell >>= sequence <<< leftClick
  await "Viz cell has not been created"
    $ map (eq 2 <<< length) getCells
  successMsg "Ok, next cell viz works"

checkSetHeightWidth :: Check Unit
checkSetHeightWidth = withSmallZipsAllChart do
  widthInput <- waitVizWidthInput
  heightInput <- waitVizHeightInput

  w <- liftEff $ randomInt 100 400
  h <- liftEff $ randomInt 100 400

  modifierKey <- getModifierKey

  sequence do
    leftClick widthInput
    selectAll modifierKey
    sendDelete
    sendKeys $ show w

    leftClick heightInput
    selectAll modifierKey
    sendDelete
    sendKeys $ show h

  await "Dimensions has not been setted" do
    dims <- getDims
    pure
       $ dims.w == pure w
      && dims.h == pure h
  successMsg "Ok, dimensions setted"

  where
  getDims = do
    canvas <- waitCanvas
    { w: _, h: _ }
      <$> (s2i <$> getCssValue canvas "width")
      <*> (s2i <$> getCssValue canvas "height")



switchToPie :: Check Unit
switchToPie = do
  getChartSwitchers >>= sequence <<< leftClick <<< _.pie
  await "Pie switch doesn't work"
    $ map pieShown getChartEditors

switchToLine :: Check Unit
switchToLine = do
 getChartSwitchers >>= sequence <<< leftClick <<< _.line
 await "Line switch doesn't work"
   $ map lineShown getChartEditors

switchToBar :: Check Unit
switchToBar = do
 getChartSwitchers >>= sequence <<< leftClick <<< _.bar
 await "Bar switch doesn't work"
   $ map barShown getChartEditors

checkSwitchers :: Check Unit
checkSwitchers = withFlatVizChart do
  editors  <- getChartEditors
  if pieShown editors
    then successMsg "Ok, initial chart type -- pie"
    else errorMsg "Incorrect initial chart type"

  switchToLine
  successMsg "pie -> line"

  switchToBar
  successMsg "line -> bar"

  switchToPie
  successMsg "bar -> pie"

  switchToBar
  successMsg "pie -> bar"

  switchToLine
  successMsg "bar -> line"

  switchToPie
  successMsg "line -> pie"

checkAlert :: Check Unit
checkAlert = withFlatVizMeasures do
  config <- getConfig
  waitExistentCss config.vizSelectors.alert "There is no alert but should"
  successMsg "ok, alert found"

checkOptions :: Check Unit
checkOptions = withFlatVizChart do
  config <- getConfig
  switchToPie
  await "incorrect pie options"
    $ map (eq config.vizOptions.flatVizAll.pie) getCurrentChartOptions
  successMsg "Ok, pie chart options are correct"

  switchToLine
  await "incorrect line options"
    $ map (eq config.vizOptions.flatVizAll.line) getCurrentChartOptions
  successMsg "Ok, line chart options are correct"

  switchToBar
  await "incorrect bar options"
    $ map (eq config.vizOptions.flatVizAll.bar) getCurrentChartOptions

  successMsg "Ok, bar chart options are correct"

-- Don't know how to name it better.
-- This test will look if after switching options in
-- category -> series1 -> series2
-- measure1 -> measure2
-- dimension -> series1 -> series2
-- are filtered
checkOptionUniqueness :: Check Unit
checkOptionUniqueness = withFlatVizChart do
  config <- getConfig

  sectionMsg "check pie uniqueness"
  switchToPie
  await "incorrect pie options"
    $ map (eq config.vizOptions.flatVizAll.pie) getCurrentChartOptions
  checkCategoryUniqueness getCategoryInput getSeriesOneInput getSeriesTwoInput

  sectionMsg "check bar uniqueness"
  switchToBar
  await "incorrect bar options"
    $ map (eq config.vizOptions.flatVizAll.bar) getCurrentChartOptions

  checkCategoryUniqueness getCategoryInput getSeriesOneInput getSeriesTwoInput

  sectionMsg "check line uniqueness"
  switchToLine
  await "incorrec line options"
    $ map (eq config.vizOptions.flatVizAll.line) getCurrentChartOptions

  checkCategoryUniqueness getDimensionInput getSeriesOneInput getSeriesTwoInput
  checkMeasureUniqueness

checkMeasureUniqueness :: Check Unit
checkMeasureUniqueness = do
  config <- getConfig
  mOne <- getMeasureOneInput
  mTwo <- getMeasureTwoInput

  toSelectOne <- filterAndGetValue mOne mTwo "measures"
  toSelectTwo <- getRandomOption mTwo

  fillSelect mTwo toSelectTwo
  fillSelect mOne toSelectTwo
  await "Options has not been dropped"
    $ map (/= toSelectTwo) $ getSelectValue mTwo

  fillSelect mTwo toSelectTwo
  fillSelect mOne config.vizOptions.clearSelection
  await "Option should be disabled"
    $ map not $ isEnabled mTwo
  successMsg "Ok, measure uniqueness"

checkCategoryUniqueness :: Check Element -> Check Element -> Check Element -> Check Unit
checkCategoryUniqueness catM serOneM serTwoM = do
  config <- getConfig
  cat <- catM
  seriesOne <- serOneM
  seriesTwo <- serTwoM

  toSelectCat <- filterAndGetValue cat seriesOne "category"
  toSelectSerOne <- filterAndGetValue seriesOne seriesTwo "series one"

  toSelectSerTwo <- getRandomOption seriesTwo
  fillSelect seriesTwo toSelectSerTwo
  fillSelect seriesOne toSelectSerTwo
  await "Options has not been dropped (one -> two)"
    $ map (/= toSelectSerTwo) $ getSelectValue seriesTwo
  successMsg "Ok, select value dropped"

  fillSelect cat toSelectSerTwo
  await "Options has not been dropped (root -> one)"
    $ map (/= toSelectSerOne) $ getSelectValue seriesOne
  successMsg "Ok, dependent selects values are dropped"

  fillSelect cat toSelectCat
  fillSelect seriesOne toSelectSerOne
  fillSelect seriesTwo toSelectSerTwo
  fillSelect cat toSelectSerTwo
  await "Optoins has not been dropped (root -> two)"
    $ map (/= toSelectSerTwo) $ getSelectValue seriesTwo

  fillSelect cat toSelectCat
  fillSelect seriesOne toSelectSerOne
  fillSelect seriesTwo toSelectSerTwo
  fillSelect seriesOne config.vizOptions.clearSelection
  await "Select should be disabled (series two)"
    $ map not $ isEnabled seriesTwo

  fillSelect seriesOne toSelectSerOne
  fillSelect seriesTwo toSelectSerTwo
  fillSelect cat config.vizOptions.clearSelection
  await "Select should be disabled (series one, series two)" do
    one <- isEnabled seriesOne
    two <- isEnabled seriesTwo
    pure $ not one && not two
  successMsg "Ok, dependent selects are disabled"

  successMsg "OK, category uniqueness"

filterAndGetValue :: Element -> Element -> String -> Check String
filterAndGetValue parent child msg = do
  toSelect <- getRandomOption parent
  fillSelect parent toSelect
  await ("Options are not filtered (" <> msg <> ")") do
    parentOptions <- optionTxts parent
    childOptions <- optionTxts child
    pure $ on eq S.fromList parentOptions (Cons toSelect childOptions)
  successMsg $ "Ok, select filtering works (" <> msg <> ")"
  pure toSelect

getSelectValue :: Element -> Check String
getSelectValue el = do
  val <- getAttribute el "value"
  getOptions (pure el) >>= foldl (foldFn val) (pure mempty)
  where
  foldFn :: String -> Check String -> Element -> Check String
  foldFn selectedVal mStr el = do
    val <- getAttribute el "value"
    if val == selectedVal
      then getInnerHtml el
      else mStr

getRandomOption :: Element -> Check String
getRandomOption el = do
  config <- getConfig
  await "there is no options"
    $ map ((> 2) <<< length) $ getOptions $ pure el
  getOptions (pure el)
    >>= traverse getInnerHtml
    >>= randomInM <<< filter (not <<< eq config.vizOptions.clearSelection)
    >>= \x -> if x == mempty
              then errorMsg "empty option list"
              else pure x
fillSelect :: Element -> String -> Check Unit
fillSelect el txt =
  sequence do
    leftClick el
    sendKeys txt
    sendEnter

optionTxts :: Element -> Check (List String)
optionTxts el = getOptions (pure el) >>= traverse getInnerHtml

checkOptionAutoSelect :: Check Unit
checkOptionAutoSelect = do
  config <- getConfig
  withFlatVizOneOption do
    switchToPie
    waitPieOrBarFullyDisabled "bar"
    pOpts <- getCurrentChartOptions
    assertBoolean "Error: incorrect pie options"
      $ pOpts == config.vizOptions.flatVizOneOption.pie

    switchToBar
    waitPieOrBarFullyDisabled "pie"
    bOpts <- getCurrentChartOptions
    assertBoolean "Error: incorrect bar options"
      $ bOpts == config.vizOptions.flatVizOneOption.bar

    switchToLine
    waitForDisabled "line"
      $ [ getSeriesOneInput
        , getSeriesTwoInput
        , getDimensionInput
        , getMeasureOneInput
        , getMeasureTwoInput
        ]
    lOpts <- getCurrentChartOptions
    assertBoolean "Error: incorrect line options"
      $ lOpts == config.vizOptions.flatVizOneOption.line
  successMsg "Ok, options are correct when there is one series and one measure"
  where
  waitForDisabled msg getters =
    await ("Error: Incorrect states of selects, they must be disabled (" <> msg <> ")")
    $ foldl (\b x -> conj <$> b <*> (map not $ x >>= isEnabled)) (pure true)
    $ getters
  waitPieOrBarFullyDisabled msg =
    waitForDisabled msg
    $ [ getSeriesOneInput
      , getSeriesTwoInput
      , getMeasureOneInput
      , getCategoryInput
      ]

checkOptionSave :: Check Unit
checkOptionSave = do
  checkOptionSaveBarOrPie switchToBar "bar"
  checkOptionSaveBarOrPie switchToPie "pie"
  checkOptionSaveLine

checkOptionSaveLine :: Check Unit
checkOptionSaveLine = withFlatVizChart do
  switchToLine
  dimension <- getDimensionInput
  measureOne <- getMeasureOneInput
  measureTwo <- getMeasureTwoInput
  seriesOne <- getSeriesOneInput
  seriesTwo <- getSeriesTwoInput

  valueDimension <- filterAndGetValue dimension seriesOne "dimension"
  valueSeriesOne <- filterAndGetValue seriesOne seriesTwo "series"
  valueSeriesTwo <- getRandomOption seriesTwo
  fillSelect seriesTwo valueSeriesTwo
  valueMeasureOne <- filterAndGetValue measureOne measureTwo "measure"
  valueMeasureTwo <- getRandomOption measureTwo
  fillSelect measureTwo valueMeasureTwo

  let assertion = do
        d <- assertSelected getDimensionInput valueDimension
        m1 <- assertSelected getMeasureOneInput valueMeasureOne
        m2 <- assertSelected getMeasureTwoInput valueMeasureTwo
        s1 <- assertSelected getSeriesOneInput valueSeriesOne
        s2 <- assertSelected getSeriesTwoInput valueSeriesTwo
        pure $ d && m1 && m2 && s1 && s2

  switchToPie
  switchToLine
  await "Error: line options have not been saved" assertion

  switchToBar
  switchToLine
  await "Error: line options have not been saved" assertion

  reloadAndSpyXHR
  waitTime $ SDConfig.autosaveTick * 2
  getChartEditors
  await "Error: line options saved but not permanently" assertion
  successMsg "Ok, line options saved"



assertSelected :: Check Element -> String -> Check Boolean
assertSelected getSelect value =
  map (eq value) $ getSelect >>= getSelectValue

checkOptionSaveBarOrPie :: Check Unit -> String -> Check Unit
checkOptionSaveBarOrPie switcher msg = withFlatVizChart do
  switcher
  category <- getCategoryInput
  measure <- getMeasureOneInput
  seriesOne <- getSeriesOneInput
  seriesTwo <- getSeriesTwoInput

  valueCategory <- filterAndGetValue category seriesOne "category"
  valueSeriesOne <- filterAndGetValue seriesOne seriesTwo "series"
  valueSeriesTwo <- getRandomOption seriesTwo
  valueMeasure <- getRandomOption measure

  fillSelect seriesTwo valueSeriesTwo
  fillSelect measure valueMeasure

  let assertion = do
        c <- assertSelected getCategoryInput valueCategory
        m <- assertSelected getMeasureOneInput valueMeasure
        s1 <- assertSelected getSeriesOneInput valueSeriesOne
        s2 <- assertSelected getSeriesTwoInput valueSeriesTwo
        pure $ c && m && s1 && s2

  switchToBar
  switcher
  await ("Error: Hasn't been saved (" <> msg <> ")") assertion

  switchToLine
  switcher
  await ("Error: Hasn't been saved (" <> msg <> ")") assertion

  switchToPie
  switcher
  await ("Error: Hasn't been saved (" <> msg <> ")") assertion

  successMsg $ "Ok, chart options have been saved (" <> msg <> ")"

  waitTime $ SDConfig.autosaveTick * 2
  reloadAndSpyXHR
  getChartEditors
  await "Error: saved, but not permanently" assertion
  successMsg $ "Ok, chart options have been saved permanently (" <> msg <> ")"

test :: Check Unit
test = do
  config <- getConfig

  sectionMsg "check next viz cell (search)"
  withSmallZipsSearchedAll $ checkNextVizCell

  sectionMsg "check next viz cell (explore)"
  withSmallZipsOpened $ checkNextVizCell

  sectionMsg "check next viz cell (query)"
  withSmallZipsQueriedAll $ checkNextVizCell

  sectionMsg "check set height/width"
  checkSetHeightWidth

  sectionMsg "check hide/show"
  withSmallZipsAllChart do
    config <- getConfig
    cell <- getCell 1
    C.checkHideShowCell cell config.cell.vizEditor

  sectionMsg "check switchers"
  checkSwitchers

  sectionMsg "alert when no available types"
  checkAlert

  sectionMsg "check availbale select options"
  checkOptions

  sectionMsg "check option filters"
  checkOptionUniqueness

  sectionMsg "check option auto select"
  checkOptionAutoSelect

  sectionMsg "check option save"
  checkOptionSave
