# Google Sheets export

Block B of the brief: every deal of the three pipelines lands in a Google Sheet at least once an hour,
one way. The script reads from Salesforce and never writes to it.

| File | What it does |
|---|---|
| [`Code.gs`](Code.gs) | The Apps Script: the "Salesforce export" menu, the hourly trigger, the login and the read-only query. |
| [`transform.js`](transform.js) | The pure logic: the query, one row per deal with the 25 columns, and the dashboard formulas. |
| [`transform.test.js`](transform.test.js) | Its tests: `node --test google-sheets/transform.test.js`, no packages needed. |
| [`appsscript.json`](appsscript.json) | The Apps Script manifest: V8, the four scopes the script needs. |

## What you get

- **Raw**: one row per deal, the brief's 25 columns, rewritten on every refresh.
- **Dashboard**: 8 blocks built from formulas over Raw (the month's funnel, conversion rates, by closer,
  by chat manager, unprocessed leads, enrollment forecast, sources with CPL and CAC, refusal reasons).
  The Month cell (B2) picks the month; it defaults to the current one.
- **Ad spend**: month, source, spend. This is the only sheet anyone types into: the CRM has no ad spend,
  and CPL and CAC need it (brief review, question 6). Leave it empty and CPL and CAC stay blank.

## Set it up

1. **A Salesforce user for the export.** Give one user the `Sheets_Export` permission set: it reads every
   deal and writes nothing. The tests prove both (`ExportTest`).
2. **An External Client App in Salesforce** (Setup, External Client App Manager, New):
   - enable OAuth with the `api` scope;
   - enable the client credentials flow and set the export user as the user it runs as;
   - copy the consumer key and secret.
3. **The spreadsheet.** Create a Google Sheet, open Extensions, Apps Script, and add two script files:
   `Code.gs` and `transform.gs` (paste `transform.js` into it). Replace the manifest with
   `appsscript.json` (Project settings, show the manifest file).
4. **The credentials**, in Project settings, Script properties. They never go into the code:
   - `SF_DOMAIN`: your My Domain URL, for example `https://your-company.my.salesforce.com`
   - `SF_CLIENT_ID`: the consumer key
   - `SF_CLIENT_SECRET`: the consumer secret
5. Reload the sheet. In the new "Salesforce export" menu, run **Refresh now** once (Google asks you to
   allow the script), then **Install hourly refresh**.

The script runs as the Google user who installed the trigger. Removing the trigger or the script
properties stops the export; nothing is left behind in Salesforce.
