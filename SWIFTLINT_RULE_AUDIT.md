# SwiftLint Disabled Rule Audit

Generated from `swiftlint rules --config .swiftlint.yml --disabled` with SwiftLint 0.64.0. The active configuration manually enables reasonable low-noise rules so behavior is stable across SwiftLint versions.

| Rule | Rationale for not enabling now |
| --- | --- |
| `accessibility_trait_for_button` | Valuable for app targets, but too UI-specific for the full package and would need view-by-view accessibility review. |
| `anonymous_argument_in_multiline_closure` | Style preference; existing closure style is mixed and this does not catch likely bugs. |
| `async_without_await` | Trial run found 58 violations; some are intentional async API-shape choices and need API review. |
| `attributes` | Formatting-only and noisy with property wrappers/macros; current formatting is already enforced by existing rules. |
| `balanced_xctest_lifecycle` | Potentially useful, but requires reviewing XCTest setup/teardown patterns package by package. |
| `blanket_disable_command` | Existing generated and migration-era disables need review before forbidding broad disables. |
| `contrasted_opening_brace` | Formatting-only; low value relative to churn. |
| `custom_rules` | No repository-specific custom rules are defined yet. |
| `direct_return` | Style preference; would churn many established functions without improving correctness. |
| `discouraged_assert` | Trial run found assertions that may be acceptable in tests or debug-only code. |
| `discouraged_default_parameter` | Public API ergonomics rely on default parameters throughout the package. |
| `discouraged_none_name` | The codebase interoperates with APIs that legitimately expose `none` values. |
| `expiring_todo` | TODO policy has not been established for this monorepo. |
| `explicit_acl` | Too verbose for the current style and high churn. |
| `explicit_enum_raw_value` | Not aligned with Swift style used in the package. |
| `explicit_self` | Analyzer rule and broad style preference; would add significant churn. |
| `explicit_top_level_acl` | Too verbose for package-internal declarations and current style. |
| `explicit_type_interface` | Too noisy for local inference-heavy Swift code. |
| `extension_access_modifier` | Style preference; current access-control placement is mixed but readable. |
| `fallthrough` | Rare and policy-specific; not worth enabling without a switch-style audit. |
| `file_header` | Headers vary across upstream-origin targets; changing policy should be a separate licensing/header pass. |
| `file_name` | Many files intentionally use extension-style names that do not match a single type exactly. |
| `final_test_case` | Correctable but broad test churn; no current evidence of performance or subclassing issues. |
| `function_default_parameter_at_end` | Existing public APIs often use defaults for call-site clarity. |
| `ibinspectable_in_extension` | Interface Builder rule is not broadly relevant to this Swift package. |
| `incompatible_concurrency_annotation` | Trial run found 256 violations; many are Swift 6 migration issues needing careful review. |
| `indentation_width` | Formatting-only and SourceKit-dependent; current indentation is handled by existing style. |
| `legacy_objc_type` | Trial run is noisy around Apple API interop and imported Objective-C types. |
| `legacy_uigraphics_function` | UIKit-specific; should be handled in UI-focused cleanup if violations matter. |
| `let_var_whitespace` | Formatting-only; low value relative to churn. |
| `local_doc_comment` | Trial run found 14 issues; useful later, but lower priority than DocC build warnings. |
| `multiline_call_arguments` | Formatting preference and high churn in API-heavy code. |
| `multiple_closures_with_trailing_closure` | Existing SwiftUI APIs intentionally use multiple trailing closures. |
| `no_empty_block` | Trial run found 210 violations, including intentional no-op closures. |
| `no_grouping_extension` | Current organization uses grouping extensions intentionally. |
| `no_magic_numbers` | Too noisy for tests, UI layout constants, and health/FHIR coding values. |
| `non_overridable_class_declaration` | Correctable style rule, but public inheritance decisions need API review. |
| `nslocalizedstring_require_bundle` | Localization patterns vary; enabling should follow a localization audit. |
| `number_separator` | Formatting-only; low correctness value. |
| `one_declaration_per_file` | Not aligned with package organization, especially small related helpers. |
| `period_spacing` | Trial run found only six style issues; can be a later formatting cleanup. |
| `prefer_asset_symbols` | Asset-symbol generation is not consistently available across targets. |
| `prefer_condition_list` | Trial run found 74 style changes; low correctness value. |
| `prefer_key_path` | Style preference; closure forms are often clearer with explicit parameters. |
| `prefer_nimble` | Project does not standardize on Nimble. |
| `prefer_self_in_static_references` | Style preference with little correctness impact. |
| `prefixed_toplevel_constant` | Current constant naming is module-scoped and would need API review. |
| `private_action` | Interface Builder rule is not broadly relevant. |
| `private_outlet` | Interface Builder rule is not broadly relevant. |
| `private_swiftui_state` | Correctable, but public/internal state wrappers need UI API review. |
| `quick_discouraged_call` | Project does not standardize on Quick. |
| `quick_discouraged_focused_test` | Project does not standardize on Quick. |
| `quick_discouraged_pending_test` | Project does not standardize on Quick. |
| `raw_value_for_camel_cased_codable_enum` | Codable raw-value policy needs API review before enforcing. |
| `redundant_final` | Correctable style rule, but final/non-final choices are part of API review. |
| `redundant_self` | Style preference; current explicit `self` is often used for clarity in closures. |
| `redundant_sendable` | Concurrency annotations are still being normalized; defer until Swift 6 migration settles. |
| `required_deinit` | Not a repository policy and would add boilerplate. |
| `required_enum_case` | No required enum-case policy is configured. |
| `shorthand_argument` | Style preference; explicit argument names often improve readability. |
| `shorthand_optional_binding` | Trial run found 47 style-only changes. |
| `sorted_enum_cases` | Current enums often preserve semantic/API ordering rather than alphabetical order. |
| `strict_fileprivate` | Access-control style preference; low correctness value. |
| `strong_iboutlet` | Interface Builder rule is not broadly relevant. |
| `superfluous_else` | Trial run found 167 style changes; low correctness value. |
| `switch_case_on_newline` | Formatting preference; would churn compact switch expressions. |
| `test_case_accessibility` | Test visibility is mixed for package and helper reuse patterns. |
| `unhandled_throwing_task` | Trial run found 7 issues; some require async error-handling decisions. |
| `unneeded_escaping` | Trial run found 11 issues; closure ABI/API changes should be reviewed separately. |
| `unneeded_synthesized_initializer` | Correctable style rule, but initializer presence is sometimes documentation/API signal. |
| `unneeded_throws_rethrows` | Trial run found 114 issues; removing throws/rethrows can be source-breaking for public APIs. |
| `unused_parameter` | Trial run found 287 issues, including protocol/conformance and callback signatures. |
| `variable_shadowing` | Common in SwiftUI and result-builder code; enabling would be noisy. |
| `vertical_whitespace_between_cases` | Trial run found 2423 style-only violations; too much churn for this pass. |
