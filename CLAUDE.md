# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

LubeLogger (repo name `lubelog`) is a self-hosted, open-source ASP.NET Core web app (net10.0) for tracking vehicle maintenance, fuel mileage, repairs, and related records. It's a classic MVC app: server-rendered Razor views for the UI plus a parallel JSON REST API used for integrations/automation.

## Build & run

```
dotnet restore
dotnet build
dotnet run
```

There is no separate test project in this repo — there are no `dotnet test` targets to run. Verify behavior by building and, where relevant, exercising the app manually.

Docker build/run uses the root `Dockerfile` (multi-stage, targets `net10.0` SDK/ASP.NET images) and `docker-compose.yml` / `docker-compose.postgresql.yml` / `docker-compose.traefik.yml` for different deployment topologies (default LiteDB, Postgres-backed, behind Traefik).

## Configuration

App config is layered via standard ASP.NET configuration providers, in `Program.cs`:
- `appsettings.json` / `appsettings.Development.json`
- an additional user config JSON file (`StaticHelper.UserConfigPath`) and server config JSON file (`StaticHelper.ServerConfigPath`)
- optional secrets directory via `LUBELOGGER_SECRETS_PATH` (key-per-file)
- locale override via `LUBELOGGER_LOCALE_OVERRIDE` / `LUBELOGGER_LOCALE_DT_OVERRIDE`

Key feature/behavior flags (`EnableAuth`, `EnableCsvImports`, `UseMPG`, `EnableShopSupplies`, `LUBELOGGER_AUTO_EVENTS`, etc.) live in `appsettings.json` and are read through `IConfigHelper` / `StaticHelper`, not hardcoded — check there before assuming a feature is always on.

## Architecture

### Layering

```
Views (Razor) / wwwroot (JS, CSS)
        |
Controllers (MVC actions + JSON API actions)
        |
Logic (business rules, cross-record orchestration)
        |
Helper (cross-cutting: config, files, mail, translations, reports)
        |
External/Interfaces + External/Implementations (data access)
        |
LiteDB (default) or Postgres (opt-in)
```

### Dual data backend, selected at startup

`Program.cs` registers one of two implementations for every `I*DataAccess` interface depending on whether `POSTGRES_CONNECTION` is set:
- Default: LiteDB implementations in `External/Implementations/Litedb/*DataAccess.cs`, all going through the singleton `ILiteDBHelper` (single `LiteDatabase` instance, file path `StaticHelper.DbName`).
- Opt-in: Postgres implementations in `External/Implementations/Postgres/*DataAccess.cs` (prefixed `PG*`), used when the `POSTGRES_CONNECTION` config value is present.

When adding a new record type or field, both implementations of the corresponding interface (in `External/Interfaces/`) need to be updated together, plus the DI registration block in `Program.cs` (both the LiteDB and Postgres branches).

### Controllers: two parallel surfaces per record type

Most record types (Notes, Gas, Service, Odometer, Reminders, Supply, Plan, Tax, Upgrade, Equipment, Inspection, Collision, Repair) have **two** controllers:
- `Controllers/Vehicle/*Controller.cs` — server-rendered actions returning partial views for the web UI, scoped under a vehicle.
- `Controllers/API/*Controller.cs` — JSON REST endpoints under `/api/vehicle/...`, implemented as `partial class APIController` (the fields/constructor live in `Controllers/APIController.cs`; each file in `Controllers/API/` adds action methods to that same partial class).

When changing behavior for a record type (e.g. notes), check whether the equivalent change is needed in both the `Vehicle` controller and the API partial class file — they intentionally duplicate similar validation/authorization logic for their respective surfaces.

### Auth model

Custom auth handler `Middleware/Authen.cs` implements a single scheme (`"AuthN"`) supporting three credential paths, tried in order: encrypted login cookie, HTTP Basic auth header, and `x-api-key` header/query param (API endpoints only, gated by `StaticHelper.GetPathAllowAPIKeyAuth`). When `EnableAuth` is `false`, every request is auto-authenticated as a synthetic root admin user — most local/dev usage runs with auth disabled, so don't assume `[Authorize]` failures reflect real permission logic unless `EnableAuth: true`.

Authorization beyond "is authenticated" is enforced via action filters in `Filter/`, not `[Authorize(Roles=...)]`:
- `CollaboratorFilter` / `StrictCollaboratorFilter` — checks the current user has the required `HouseholdPermission` (View/Edit/Delete) on the `vehicleId`/`vehicleIds` in the action arguments, via `IUserLogic.UserCanEditVehicle`. Root users bypass this.
- `APIKeyFilter` — enforces permission checks specific to API-key authenticated requests.
- `QueryParamFilter` — validates required query params are present before the action runs.

These are applied via `[TypeFilter(typeof(...), Arguments = new object[] {...})]` on individual actions — the constructor args (bool flags, `HouseholdPermission`) matter and vary per action (e.g. single vs. multiple vehicle ids, JSON vs. redirect error response).

### Events / webhooks

`Logic/Event/` (`IEventLogic`/`EventLogic`, `EventHubLogic`) publishes domain events (e.g. `note.add.api`) both over SignalR (`/api/ws` hub) and to configured webhooks (`WebHookPayload.From*Record` builders). API actions that mutate data call `_eventLogic.PublishEvent(...)` after a successful write — follow this pattern for new mutating endpoints. `AutomatedEventLogic` is a hosted service, only registered when `LUBELOGGER_AUTO_EVENTS` is enabled.

### Static file serving

`Program.cs` wires up separate `UseStaticFiles` middleware for `data/images`, `data/documents`, and `data/temp` (uploaded content, outside `wwwroot`), each with `OnPrepareResponse` redirecting unauthenticated requests to `/Login`. `data/translations` is served without that auth check. Don't assume all static content goes through `wwwroot`.

### Extensibility patterns to know

- `ExtraField` / `IExtraFieldDataAccess` — user-defined custom fields attachable to records; most record models carry an `ExtraFields` collection.
- `MapProfile/ImportMappers.cs` — CsvHelper class maps for CSV import/export, keyed per record type.
- `Helper/TranslationHelper.cs` + `data/translations` — i18n; UI strings are looked up rather than hardcoded in Razor views where localization matters.
- `Enum/` — many small enums (`HouseholdPermission`, `ReminderUrgency`, `PlanPriority`, etc.) drive filter/permission/UI logic; check these before adding new status/kind fields as a raw string or int.
