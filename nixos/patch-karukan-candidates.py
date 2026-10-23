"""Bound unsolicited completion length in the pinned Karukan engine."""
from pathlib import Path
import sys


def replace(root, name, old, new):
    path = root / name
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f'{name}: expected one match for {old!r}')
    path.write_text(text.replace(old, new))


def main(root, module):
    core = 'karukan-im/core/src/core/engine/'
    (root / core / 'candidate_limits.rs').write_text(module.read_text())
    replace(root, core + 'mod.rs', 'mod cache;', 'mod cache;\nmod candidate_limits;')
    # Filter after dispatch so synchronous, background, beam and cached model
    # answers share the same policy. An empty result uses the usual kana fallback.
    replace(root, core + 'model.rs',
            '        candidates\n    }\n\n    /// One model computation,',
            '        candidate_limits::filter_model_candidates(reading, candidates)\n'
            '    }\n\n    /// One model computation,')
    # Obtain the whole already-ranked pool before counting accepted predictions;
    # otherwise long completions could consume all three suggestion slots.
    replace(root, core + 'conversion.rs',
            'dict.predictive_search(reading, budget)',
            'dict.predictive_search(reading, usize::MAX)')
    replace(root, core + 'conversion.rs',
            'dict.predictive_search_expanded(reading, expansions, budget)',
            'dict.predictive_search_expanded(reading, expansions, usize::MAX)')
    replace(root, core + 'conversion.rs',
            '                for m in matches {\n',
            '                for m in matches {\n'
            '                    if !candidate_limits::within_limit(reading, m.reading) {\n'
            '                        continue;\n                    }\n')
    replace(root, core + 'conversion.rs',
            '            if full_reading == reading {\n',
            '            if !candidate_limits::within_limit(reading, &full_reading) {\n'
            '                continue;\n            }\n'
            '            if full_reading == reading {\n')
    # The upstream fixture deliberately expected unlimited completion. Keep
    # testing paging/count separately from the new reading-length constraint.
    replace(root, core + 'tests/predictive.rs',
            '            conversion.contains(&surface.to_string()),\n'
            '            "missing {surface}"',
            '            conversion.contains(&surface.to_string())\n'
            '                == matches!(surface, "早稲田" | "早稲田市"),\n'
            '            "unexpected completion policy for {surface}"')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))
