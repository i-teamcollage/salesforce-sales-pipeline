// Tests of the Google Sheets export: node --test google-sheets/   (no packages needed)
// Test names start with the brief's requirement id, so docs/traceability.md can find them.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const t = require('./transform.js');

const CODE = fs.readFileSync(path.join(__dirname, 'Code.gs'), 'utf8');

const BRIEF_COLUMNS = [
  'Deal ID', 'Pipeline', 'Stage', 'Created', 'Source', 'Request type', 'Grade', 'Segment', 'Lead author',
  'Closer', 'Key call booked on', 'Key call date and time', 'Key call outcome', 'Key call result', 'Objection',
  'Prepayment date', 'Payment method', 'Full payment date', 'Amount', 'Start period', 'Refusal reason',
  'Refusal type', 'First response time', 'Last activity date', 'Close date'
];

/** A deal as the Salesforce REST API returns it. Every name here is made up. */
function record(overrides) {
  return Object.assign({
    attributes: { type: 'Opportunity' },
    Id: '006000000000001AAA',
    RecordType: { Name: 'New clients' },
    StageName: 'Closed Won',
    CreatedDate: '2026-10-03T08:15:00.000+0000',
    Source__c: 'Paid social',
    Request_Type__c: 'Application',
    Grade__c: 'A',
    Segment__c: 'Manager',
    Lead_Author__r: { Name: 'Lina Petrov' },
    Closer__r: { Name: 'Omar Haddad' },
    Key_Call_Booked_On__c: '2026-10-04',
    Key_Call_At__c: '2026-10-06T14:00:00.000+0000',
    Key_Call_Outcome__c: 'Held',
    Key_Call_Result__c: 'Purchase',
    Objection__c: 'Price',
    Prepayment_Date__c: '2026-10-07',
    Payment_Method__c: 'Single payment',
    Full_Payment_Date__c: '2026-10-12',
    Amount: 2400,
    Start_Period__c: '2026-11',
    Refusal_Reason__c: null,
    Refusal_Type__c: null,
    First_Response_At__c: '2026-10-03T08:31:00.000+0000',
    LastActivityDate: '2026-10-12',
    CloseDate: '2026-10-12',
    IsClosed: true
  }, overrides);
}

function cell(row, header) {
  return row[BRIEF_COLUMNS.indexOf(header)];
}

test('EX3 the Raw sheet has the 25 columns of the brief, in its order', () => {
  const [header] = t.rowsFromRecords([]);
  assert.deepEqual(header, BRIEF_COLUMNS);
  assert.equal(t.COLUMNS.length, 25);
});

test('EX3 one row per deal, dates as dates, people by name', () => {
  const rows = t.rowsFromRecords([record(), record({ Id: '006000000000002AAA', StageName: 'Warm-up' })]);
  assert.equal(rows.length, 3, 'header plus one row per deal');
  const row = rows[1];
  assert.equal(cell(row, 'Deal ID'), '006000000000001AAA');
  assert.equal(cell(row, 'Pipeline'), 'New clients');
  assert.equal(cell(row, 'Lead author'), 'Lina Petrov');
  assert.equal(cell(row, 'Closer'), 'Omar Haddad');
  assert.equal(cell(row, 'Amount'), 2400);
  assert.equal(cell(row, 'Created').toISOString(), '2026-10-03T08:15:00.000Z', 'an exact instant');
  const booked = cell(row, 'Key call booked on');
  assert.deepEqual([booked.getFullYear(), booked.getMonth(), booked.getDate()], [2026, 9, 4], 'a calendar date');
  assert.equal(cell(row, 'Refusal reason'), '', 'empty fields stay empty');
  assert.equal(cell(rows[2], 'Stage'), 'Warm-up');
});

test('EX3 missing lookups and open deals leave cells blank', () => {
  const row = t.rowFromRecord(record({ Closer__r: null, IsClosed: false, Amount: null }));
  assert.equal(cell(row, 'Closer'), '');
  assert.equal(cell(row, 'Amount'), '');
  assert.equal(cell(row, 'Close date'), '', 'an open deal has no close date yet');
  const closed = t.rowFromRecord(record());
  assert.ok(cell(closed, 'Close date') instanceof Date, 'a closed deal shows the day it closed');
});

test('EX3 the query reads every column and only the three pipelines', () => {
  const select = t.EXPORT_SOQL.match(/^SELECT (.*) FROM Opportunity/)[1].split(',').map((s) => s.trim());
  const wanted = t.COLUMNS.map((column) => column.path).concat(['IsClosed']);
  assert.deepEqual([...select].sort(), [...wanted].sort(), 'exactly the fields the columns need');
  assert.match(t.EXPORT_SOQL, /WHERE RecordType\.DeveloperName IN \('New_Clients', 'Reactivation', 'Repeat_Sales'\)/);
});

test('EX3 column letters', () => {
  assert.equal(t.columnLetter(0), 'A');
  assert.equal(t.columnLetter(24), 'Y');
  assert.equal(t.columnLetter(26), 'AA');
  assert.equal(t.rawRange('closer'), 'Raw!$J:$J');
});

test('EX2 the export runs at least hourly and has a manual run', () => {
  assert.match(CODE, /ScriptApp\.newTrigger\('refresh'\)\.timeBased\(\)\.everyHours\(1\)\.create\(\)/);
  assert.match(CODE, /\.addItem\('Refresh now', 'refresh'\)/);
  assert.match(CODE, /function onOpen\(\)/);
  assert.match(CODE, /function refresh\(\)/);
});

test('EX1 the script only reads from Salesforce', () => {
  const methods = [...CODE.matchAll(/method: '(\w+)'/g)].map((m) => m[1]);
  assert.deepEqual(methods.sort(), ['get', 'post'], 'one GET loop and one token request');
  assert.match(CODE, /\/services\/oauth2\/token/, 'the only POST is the login');
  assert.doesNotMatch(CODE, /sobjects|composite|'patch'|'put'|'delete'/i, 'no write endpoints at all');
  assert.doesNotMatch(CODE, /SF_CLIENT_SECRET\s*=\s*'/, 'no secret in the code');
});

// ---- Dashboard ----------------------------------------------------------------------------

const OCTOBER = { month: new Date(2026, 9, 1), now: new Date('2026-10-20T12:00:00Z') };

/** Seven made-up deals: six created in October, one in September. */
function sampleRows() {
  const deals = [
    record({ Id: 'd1' }),
    record({ Id: 'd2', StageName: 'Key call held', CreatedDate: '2026-10-10T09:00:00.000+0000', Source__c: 'Search ads',
      Key_Call_Booked_On__c: '2026-10-11', Key_Call_Result__c: 'Thinking', Prepayment_Date__c: null,
      Full_Payment_Date__c: null, Start_Period__c: null, Amount: 2400, IsClosed: false }),
    record({ Id: 'd3', StageName: 'Prepayment received', CreatedDate: '2026-10-15T09:00:00.000+0000',
      Closer__r: { Name: 'Sara Lind' }, Key_Call_Booked_On__c: '2026-10-16', Prepayment_Date__c: '2026-10-18',
      Full_Payment_Date__c: null, Amount: 3100, IsClosed: false }),
    record({ Id: 'd4', StageName: 'New lead', CreatedDate: '2026-10-20T11:50:00.000+0000', Source__c: 'Website',
      First_Response_At__c: null, Closer__r: null, Key_Call_Booked_On__c: null, Key_Call_Outcome__c: null,
      Key_Call_Result__c: null, Prepayment_Date__c: null, Full_Payment_Date__c: null, Start_Period__c: null, IsClosed: false }),
    record({ Id: 'd5', StageName: 'New lead', CreatedDate: '2026-10-19T09:00:00.000+0000', Source__c: 'Website',
      First_Response_At__c: null, Closer__r: null, Key_Call_Booked_On__c: null, Key_Call_Outcome__c: null,
      Key_Call_Result__c: null, Prepayment_Date__c: null, Full_Payment_Date__c: null, Start_Period__c: null, IsClosed: false }),
    record({ Id: 'd6', RecordType: { Name: 'Reactivation' }, StageName: 'Deferred demand', CreatedDate: '2026-09-20T09:00:00.000+0000',
      Source__c: 'Search ads', Refusal_Reason__c: 'Price', Refusal_Type__c: 'True refusal', Closer__r: null,
      Key_Call_Booked_On__c: null, Key_Call_Outcome__c: null, Key_Call_Result__c: null, Prepayment_Date__c: null,
      Full_Payment_Date__c: null, Start_Period__c: null, IsClosed: false }),
    record({ Id: 'd7', RecordType: { Name: 'Reactivation' }, StageName: 'Ignored', CreatedDate: '2026-10-05T09:00:00.000+0000',
      Source__c: 'Website', Refusal_Reason__c: 'No reply', Refusal_Type__c: 'Ignored', Closer__r: null,
      Key_Call_Booked_On__c: null, Key_Call_Outcome__c: null, Key_Call_Result__c: null, Prepayment_Date__c: null,
      Full_Payment_Date__c: null, Start_Period__c: null, IsClosed: false })
  ];
  return t.rowsFromRecords(deals).slice(1);
}

function block(number) {
  return t.dashboardBlocks()[number - 1];
}

function evaluateRows(definition, rows) {
  const out = {};
  definition.rows.filter((m) => m.count).forEach((m) => { out[m.label] = t.countRows(rows, m.count, OCTOBER); });
  return out;
}

function evaluateList(definition, rows) {
  const out = {};
  t.listNames(rows, definition.listOf).forEach((name) => {
    const context = Object.assign({}, OCTOBER, { name });
    const byName = [[definition.listOf, 'is', { cell: 'name' }]];
    out[name] = {};
    definition.columns.forEach((c) => {
      if (c.count) out[name][c.header] = t.countRows(rows, byName.concat(c.count), context);
      if (c.sum) out[name][c.header] = t.sumRows(rows, c.sum, byName.concat(c.where), context);
    });
  });
  return out;
}

/** The number of arguments of every call to a function in a formula, ignoring commas in quotes. */
function argumentCounts(formula, name) {
  const counts = [];
  for (let start = formula.indexOf(name + '('); start !== -1; start = formula.indexOf(name + '(', start + 1)) {
    let depth = 0;
    let inQuote = false;
    let args = 1;
    for (let i = start + name.length; i < formula.length; i++) {
      const ch = formula[i];
      if (ch === '"') {
        inQuote = !inQuote;
      } else if (!inQuote && ch === '(') {
        depth += 1;
      } else if (!inQuote && ch === ')') {
        depth -= 1;
        if (depth === 0) break;
      } else if (!inQuote && ch === ',' && depth === 1) {
        args += 1;
      }
    }
    counts.push(args);
  }
  return counts;
}

test('EX4 the dashboard has the 8 blocks of the brief', () => {
  const titles = t.dashboardBlocks().map((b) => b.title);
  const expected = [/funnel of the month/i, /conversion/i, /by closer/i, /by chat manager/i, /unprocessed leads/i,
    /enrollment forecast/i, /CPL and CAC/, /refusal reasons/i];
  assert.equal(titles.length, 8);
  expected.forEach((pattern, i) => assert.match(titles[i], pattern));
});

test('EX4 every dashboard formula is well formed and reads only Raw, Ad spend or the dashboard', () => {
  const formulas = t.dashboardCells().map((c) => String(c.value)).filter((v) => v.startsWith('='));
  assert.ok(formulas.length > 100, 'blocks are built from formulas');
  formulas.forEach((f) => {
    assert.equal((f.match(/\(/g) || []).length, (f.match(/\)/g) || []).length, 'balanced parentheses: ' + f);
    assert.equal((f.match(/"/g) || []).length % 2, 0, 'balanced quotes: ' + f);
    for (const ref of f.matchAll(/(\w+|'[^']+')!\$?([A-Z]+)/g)) {
      assert.ok(['Raw', "'Ad spend'"].includes(ref[1]), 'unknown sheet in ' + f);
      if (ref[1] === 'Raw') assert.ok(ref[2] <= 'Y' && ref[2].length === 1, 'Raw has columns A to Y: ' + f);
    }
    argumentCounts(f, 'COUNTIFS').forEach((n) => assert.equal(n % 2, 0, 'COUNTIFS takes range and criterion pairs: ' + f));
    argumentCounts(f, 'SUMIFS').forEach((n) => assert.equal(n % 2, 1, 'SUMIFS takes a sum range, then pairs: ' + f));
  });
});

test('EX4 the funnel and the conversion rates count the deals of the month', () => {
  assert.deepEqual(evaluateRows(block(1), sampleRows()), {
    'New deals': 6, 'First response given': 4, 'Key call booked': 3, 'Key call held': 3,
    'Prepayment received': 2, 'Paid in full': 1
  });
  const cells = t.dashboardCells();
  const label = (text) => cells.find((c) => c.value === text);
  const rate = cells.find((c) => c.row === label('Lead to key call booked').row && c.col === 2);
  assert.equal(rate.value, `=IFERROR(B${label('Key call booked').row}/B${label('New deals').row},"")`);
});

test('EX4 by closer and by chat manager', () => {
  assert.deepEqual(evaluateList(block(3), sampleRows()), {
    'Omar Haddad': { 'Calls booked': 2, 'Calls held': 2, Purchases: 1, Prepayments: 1, Revenue: 2400 },
    'Sara Lind': { 'Calls booked': 1, 'Calls held': 1, Purchases: 1, Prepayments: 1, Revenue: 0 }
  });
  assert.deepEqual(evaluateList(block(4), sampleRows()), {
    'Lina Petrov': { Leads: 6, Answered: 4, 'Key calls booked': 3, Prepayments: 2 }
  });
});

test('EX4 unprocessed leads are New lead deals with no reply yet', () => {
  assert.deepEqual(evaluateRows(block(5), sampleRows()), {
    'New leads with no reply yet': 2, 'of which waiting over 30 minutes': 1
  });
});

test('EX4 enrollment forecast, sources and refusal reasons', () => {
  const forecast = evaluateList(block(6), sampleRows());
  assert.deepEqual(forecast['2026-11'], { 'Prepaid, not yet in full': 1, 'Paid in full': 1, 'Amount paid in full': 2400 });
  assert.deepEqual(evaluateList(block(7), sampleRows()), {
    'Paid social': { Leads: 2, Customers: 1 }, 'Search ads': { Leads: 1, Customers: 0 }, Website: { Leads: 3, Customers: 0 }
  });
  assert.deepEqual(evaluateList(block(8), sampleRows()), { 'No reply': { Deals: 1 }, Price: { Deals: 1 } });
});

test('EX4 CPL and CAC use the Ad spend sheet and stay empty without spend', () => {
  const formulas = t.dashboardCells().map((c) => String(c.value));
  assert.ok(formulas.some((f) => f.includes("SUMIFS('Ad spend'!$C:$C,'Ad spend'!$A:$A,$B$2,'Ad spend'!$B:$B,$A")));
  assert.ok(formulas.some((f) => /IF\(OR\(D\d+=0,B\d+=0\),"",D\d+\/B\d+\)/.test(f)), 'CPL = spend / leads');
  assert.ok(formulas.some((f) => /IF\(OR\(D\d+=0,C\d+=0\),"",D\d+\/C\d+\)/.test(f)), 'CAC = spend / customers');
  assert.deepEqual(t.AD_SPEND_HEADER, ['Month (first day)', 'Source', 'Spend']);
});

test('EX4 text inside formulas is quoted safely', () => {
  assert.equal(t.quoted('say "hi"'), '"say ""hi"""');
  assert.deepEqual(t.criteriaArgs([['stage', 'is', 'New lead']]), ['Raw!$C:$C', '"New lead"']);
  assert.throws(() => t.criteriaArgs([['stage', 'near', 'x']]), /Unknown operator/);
});
