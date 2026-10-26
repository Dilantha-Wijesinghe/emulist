# 3. No third-party looks in the repository

- Status: accepted
- Date: 2026-10-22

## Context

People want the looks they know: Fujifilm's film simulations, film recipes,
commercial emulation plugins. Their LUTs and profiles belong to their makers.

## Decision

- Emulist's own stocks are original creative interpretations, not
  measurements of commercial film stocks.
- Fujifilm's official LUTs are downloaded by the user, on request, from
  fujifilm-x.com, and installed in their Application Support folder. They are
  never bundled or redistributed.
- Recipes are published settings (with a link to each recipe's page), applied
  through Emulist's own controls.
- Anything else comes in as a `.cube` file the user imports. Material
  extracted or reverse-engineered from commercial software is not accepted.

## Consequences

- The repository and its releases contain only original work.
- Fujifilm's simulations and the recipes built on them appear only after the
  download.
