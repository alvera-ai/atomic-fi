alias Credo.Check.Consistency.MultiAliasImportRequireUse
alias Credo.Check.Consistency.ParameterPatternMatching
alias Credo.Check.Readability.AliasOrder
alias Credo.Check.Readability.BlockPipe
alias Credo.Check.Readability.LargeNumbers
alias Credo.Check.Readability.ModuleDoc
alias Credo.Check.Readability.MultiAlias
alias Credo.Check.Readability.OneArityFunctionInPipe
alias Credo.Check.Readability.ParenthesesOnZeroArityDefs
alias Credo.Check.Readability.PipeIntoAnonymousFunctions
alias Credo.Check.Readability.PreferImplicitTry
alias Credo.Check.Readability.SinglePipe
alias Credo.Check.Readability.StrictModuleLayout
alias Credo.Check.Readability.UnnecessaryAliasExpansion
alias Credo.Check.Readability.WithSingleClause
alias Credo.Check.Refactor.CondStatements
alias Credo.Check.Refactor.FilterCount
alias Credo.Check.Refactor.MapJoin
alias Credo.Check.Refactor.NegatedConditionsInUnless
alias Credo.Check.Refactor.NegatedConditionsWithElse
alias Credo.Check.Refactor.PipeChainStart
alias Credo.Check.Refactor.RedundantWithClauseResult
alias Credo.Check.Refactor.UnlessWithElse
alias Credo.Check.Refactor.WithClauses

# This file contains the configuration for Credo and you are probably reading
# this after creating it with `mix credo.gen.config`.
#
# If you find anything wrong or unclear in this file, please report an
# issue on GitHub: https://github.com/rrrene/credo/issues
#
%{
  #
  # You can have as many configs as you like in the `configs:` field.
  configs: [
    %{
      #
      # Run any config using `mix credo -C <name>`. If no config name is given
      # "default" is used.
      #
      name: "default",
      #
      # These are the files included in the analysis:
      files: %{
        #
        # You can give explicit globs or simply directories.
        # In the latter case `**/*.{ex,exs}` will be used.
        #
        included: [
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      #
      # Load and configure plugins here:
      #
      plugins: [],
      #
      # If you create your own checks, you must specify the source files for
      # them here, so they can be loaded by Credo before running the analysis.
      #
      requires: [],
      #
      # If you want to enforce a style guide and need a more traditional linting
      # experience, you can change `strict` to `true` below:
      #
      strict: false,
      #
      # To modify the timeout for parsing files, change this value:
      #
      parse_timeout: 5000,
      #
      # If you want to use uncolored output by default, you can change `color`
      # to `false` below:
      #
      color: true,
      #
      # You can customize the parameters of any check by adding a second element
      # to the tuple.
      #
      # To disable a check put `false` as second element:
      #
      #     {Credo.Check.Design.DuplicatedCode, false}
      #
      checks: %{
        enabled: [
          #
          ## Consistency Checks
          #
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          #
          ## Design Checks
          #
          # You can customize the priority of any check
          # Priority values are: `low, normal, high, higher`
          #
          {Credo.Check.Design.AliasUsage, [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 0]},
          {Credo.Check.Design.TagFIXME, []},
          # You can also customize the exit_status of each check.
          # If you don't want TODO comments to cause `mix credo` to fail, just
          # set this value to 0 (zero).
          #
          {Credo.Check.Design.TagTODO, [exit_status: 2]},

          #
          ## Readability Checks
          #
          {AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {LargeNumbers, []},
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {ParenthesesOnZeroArityDefs, []},
          {PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {WithSingleClause, []},

          #
          ## Refactoring Opportunities
          #
          {Credo.Check.Refactor.Apply, []},
          {CondStatements, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {FilterCount, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {MapJoin, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {NegatedConditionsInUnless, []},
          {NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, []},
          {RedundantWithClauseResult, []},
          {Credo.Check.Refactor.RejectReject, []},
          {UnlessWithElse, []},
          {WithClauses, []},

          #
          ## Warnings
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []}
        ],
        disabled: [
          #
          # Checks scheduled for next check update (opt-in for now, just replace `false` with `[]`)

          #
          # Controversial and experimental checks (opt-in, just move the check to `:enabled`
          #   and be sure to use `mix credo --strict` to see low priority checks)
          #
          {MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.DuplicatedCode, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Readability.AliasAs, []},
          {BlockPipe, []},
          {Credo.Check.Readability.ImplTrue, []},
          {MultiAlias, []},
          {Credo.Check.Readability.NestedFunctionCalls, []},
          {OneArityFunctionInPipe, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.SeparateAliasRequire, []},
          {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          {SinglePipe, []},
          {Credo.Check.Readability.Specs, []},
          {StrictModuleLayout, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.IoPuts, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {PipeChainStart, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MixEnv, []},
          {Credo.Check.Warning.UnsafeToAtom, []},

          # Styler Rewrites
          #
          # The following rules are automatically rewritten by Styler and so disabled here to save time
          # Some of the rules have `priority: :high`, meaning Credo runs them unless we explicitly disable them
          # (removing them from this file wouldn't be enough, the `false` is required)
          #
          # Some rules have a comment before them explaining ways Styler deviates from the Credo rule.
          #
          # always expands `A.{B, C}`
          {MultiAliasImportRequireUse, false},
          # including `case`, `fn` and `with` statements
          {ParameterPatternMatching, false},
          {AliasOrder, false},
          {BlockPipe, false},
          # goes further than formatter - fixes bad underscores, eg: `100_00` -> `10_000`
          {LargeNumbers, false},
          # adds `@moduledoc false`
          {ModuleDoc, false},
          {MultiAlias, false},
          {OneArityFunctionInPipe, false},
          # removes parens
          {ParenthesesOnZeroArityDefs, false},
          {PipeIntoAnonymousFunctions, false},
          {PreferImplicitTry, false},
          {SinglePipe, false},
          # **potentially breaks compilation** - see **Troubleshooting** section below
          {StrictModuleLayout, false},
          {UnnecessaryAliasExpansion, false},
          {WithSingleClause, false},
          {Credo.Check.Refactor.CaseTrivialMatches, false},
          {CondStatements, false},
          # in pipes only
          {FilterCount, false},
          # in pipes only
          {Credo.Check.Refactor.MapInto, false},
          # in pipes only
          {MapJoin, false},
          {NegatedConditionsInUnless, false},
          {NegatedConditionsWithElse, false},
          # allows ecto's `from
          {PipeChainStart, false},
          {RedundantWithClauseResult, false},
          {UnlessWithElse, false},
          {WithClauses, false}

          #
          # Custom checks can be created using `mix credo.gen.check`.
          #
        ]
      }
    }
  ]
}
