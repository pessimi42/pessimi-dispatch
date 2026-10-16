# Dispatcher job

The resource looks for the job names in `Config.Dispatcher.jobs` (default `dispatch`).
Add the job to your framework with one of the snippets below.

## Qbox – `qbx_core/shared/jobs.lua`

```lua
['dispatch'] = {
    label = 'Hätäkeskus',
    type = 'dispatch',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        [0] = { name = 'Harjoittelija', payment = 50 },
        [1] = { name = 'Päivystäjä', payment = 75 },
        [2] = { name = 'Vuoromestari', isboss = true, bankAuth = true, payment = 100 },
    },
},
```

## QBCore – `qb-core/shared/jobs.lua`

```lua
['dispatch'] = {
    label = 'Emergency Dispatch',
    type = 'dispatch',
    defaultDuty = false,
    offDutyPay = false,
    grades = {
        ['0'] = { name = 'Trainee', payment = 50 },
        ['1'] = { name = 'Dispatcher', payment = 75 },
        ['2'] = { name = 'Shift Supervisor', isboss = true, payment = 100 },
    },
},
```

## ESX – SQL

```sql
INSERT INTO `jobs` (`name`, `label`) VALUES ('dispatch', 'Emergency Dispatch');

INSERT INTO `job_grades` (`job_name`, `grade`, `name`, `label`, `salary`, `skin_male`, `skin_female`) VALUES
  ('dispatch', 0, 'trainee',    'Trainee',          200, '{}', '{}'),
  ('dispatch', 1, 'dispatcher', 'Dispatcher',       300, '{}', '{}'),
  ('dispatch', 2, 'supervisor', 'Shift Supervisor', 400, '{}', '{}');
```

ESX Legacy 1.10+ supports duty (`/dispatchduty` works). On older ESX the dispatcher is
always on duty while employed.

## Standalone (no framework) – `server.cfg`

```
add_ace group.dispatch pessimi-dispatch.dispatcher allow
add_ace group.police   pessimi-dispatch.service.police allow
add_ace group.ems      pessimi-dispatch.service.ems allow
```
