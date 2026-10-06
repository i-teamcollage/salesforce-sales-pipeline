/**
 * Google Sheets export of the Salesforce deals (brief, Block B).
 *
 * EX1  One way: this script only reads from Salesforce (one token request, then GET queries).
 * EX2  At least hourly (installHourlyTrigger) plus a manual run (menu "Salesforce export" > "Refresh now").
 * EX3  The Raw sheet: one row per deal, the 25 columns of the brief (transform.js).
 * EX4  The Dashboard sheet: 8 blocks of formulas over Raw (transform.js).
 *
 * Credentials live in the script properties, never in the code or the repository:
 *   SF_DOMAIN         https://your-domain.my.salesforce.com
 *   SF_CLIENT_ID      consumer key of the External Client App (client credentials flow)
 *   SF_CLIENT_SECRET  its consumer secret
 * Setup steps: google-sheets/README.md.
 */

var API_VERSION = 'v67.0';

function onOpen() {
  SpreadsheetApp.getUi()
    .createMenu('Salesforce export')
    .addItem('Refresh now', 'refresh')
    .addItem('Rebuild dashboard', 'rebuildDashboard')
    .addItem('Install hourly refresh', 'installHourlyTrigger')
    .addToUi();
}

/** Runs refresh every hour. Safe to run again: it replaces its own trigger. */
function installHourlyTrigger() {
  ScriptApp.getProjectTriggers().forEach(function (trigger) {
    if (trigger.getHandlerFunction() === 'refresh') {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  ScriptApp.newTrigger('refresh').timeBased().everyHours(1).create();
}

function refresh() {
  var records = fetchDeals_();
  writeRaw_(rowsFromRecords(records));
  ensureSheet_(AD_SPEND_SHEET, AD_SPEND_HEADER);
  if (!SpreadsheetApp.getActive().getSheetByName(DASHBOARD_SHEET)) {
    rebuildDashboard();
  }
}

/** All deals of the three pipelines, following Salesforce's pagination. */
function fetchDeals_() {
  var properties = PropertiesService.getScriptProperties();
  var domain = properties.getProperty('SF_DOMAIN');
  var token = accessToken_(domain, properties.getProperty('SF_CLIENT_ID'), properties.getProperty('SF_CLIENT_SECRET'));
  var url = domain + '/services/data/' + API_VERSION + '/query?q=' + encodeURIComponent(EXPORT_SOQL);
  var records = [];
  while (url) {
    var response = UrlFetchApp.fetch(url, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token },
      muteHttpExceptions: true
    });
    if (response.getResponseCode() !== 200) {
      throw new Error('Salesforce query failed: ' + response.getContentText());
    }
    var body = JSON.parse(response.getContentText());
    records = records.concat(body.records);
    url = body.nextRecordsUrl ? domain + body.nextRecordsUrl : null;
  }
  return records;
}

/** OAuth 2.0 client credentials flow: the External Client App runs as the export user. */
function accessToken_(domain, clientId, clientSecret) {
  var response = UrlFetchApp.fetch(domain + '/services/oauth2/token', {
    method: 'post',
    payload: { grant_type: 'client_credentials', client_id: clientId, client_secret: clientSecret },
    muteHttpExceptions: true
  });
  if (response.getResponseCode() !== 200) {
    throw new Error('Salesforce login failed: ' + response.getContentText());
  }
  return JSON.parse(response.getContentText()).access_token;
}

function writeRaw_(rows) {
  var sheet = ensureSheet_(RAW_SHEET);
  sheet.clearContents();
  sheet.getRange(1, 1, rows.length, rows[0].length).setValues(rows);
  sheet.setFrozenRows(1);
}

function rebuildDashboard() {
  var sheet = ensureSheet_(DASHBOARD_SHEET);
  sheet.clear();
  dashboardCells().forEach(function (cell) {
    var range = sheet.getRange(cell.row, cell.col);
    if (String(cell.value).charAt(0) === '=') {
      range.setFormula(cell.value);
    } else {
      range.setValue(cell.value);
    }
    if (cell.bold) {
      range.setFontWeight('bold');
    }
    if (cell.format) {
      range.setNumberFormat(cell.format);
    }
  });
}

function ensureSheet_(name, header) {
  var spreadsheet = SpreadsheetApp.getActive();
  var sheet = spreadsheet.getSheetByName(name) || spreadsheet.insertSheet(name);
  if (header && sheet.getLastRow() === 0) {
    sheet.getRange(1, 1, 1, header.length).setValues([header]);
  }
  return sheet;
}
