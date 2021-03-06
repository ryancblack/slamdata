{-
Copyright 2016 SlamData, Inc.

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

module SlamData.Notebook.Cell.Explore.Component.Query where

import Prelude

import Data.Functor.Coproduct (Coproduct())

import Halogen (ChildF())

import SlamData.Notebook.Cell.Common.EvalQuery (CellEvalQuery())
import SlamData.Notebook.FileInput.Component as FI

data Query a = UpdateExplore String a

type QueryP = Coproduct CellEvalQuery (ChildF Unit FI.Query)
