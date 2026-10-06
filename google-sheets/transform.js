/**
 * The pure logic of the Google Sheets export (brief, Block B): which deals and columns are read,
 * how a Salesforce record becomes one row of the "Raw" sheet (EX3), and the formulas of the
 * "Dashboard" sheet (EX4). No Google or Salesforce calls here, so Node can test all of it.
 *
 * In Apps Script this file is a second script file next to Code.gs (they share one scope).
 * In Node it is loaded with require().
 */

var RAW_SHEET = 'Raw';
var DASHBOARD_SHEET = 'Dashboard';
var AD_SPEND_SHEET = 'Ad spend';
var AD_SPEND_HEADER = ['Month (first day)', 'Source', 'Spend'];

// export-query:start
var EXPORT_SOQL =
  'SELECT Id, RecordType.Name, StageName, CreatedDate, Source__c, Request_Type__c, Grade__c, Segment__c, ' +
  'Lead_Author__r.Name, Closer__r.Name, Key_Call_Booked_On__c, Key_Call_At__c, Key_Call_Outcome__c, ' +
  'Key_Call_Result__c, Objection__c, Prepayment_Date__c, Payment_Method__c, Full_Payment_Date__c, Amount, ' +
  'Start_Period__c, Refusal_Reason__c, Refusal_Type__c, First_Response_At__c, LastActivityDate, CloseDate, ' +
  'IsClosed FROM Opportunity ' +
  "WHERE RecordType.DeveloperName IN ('New_Clients', 'Reactivation', 'Repeat_Sales') ORDER BY CreatedDate";
// export-query:end

/** The 25 columns of the brief, in its order. `path` is the Salesforce field read for the column. */
var COLUMNS = [
  { key: 'id', header: 'Deal ID', path: 'Id', type: 'text' },
  { key: 'pipeline', header: 'Pipeline', path: 'RecordType.Name', type: 'text' },
  { key: 'stage', header: 'Stage', path: 'StageName', type: 'text' },
  { key: 'created', header: 'Created', path: 'CreatedDate', type: 'datetime' },
  { key: 'source', header: 'Source', path: 'Source__c', type: 'text' },
  { key: 'requestType', header: 'Request type', path: 'Request_Type__c', type: 'text' },
  { key: 'grade', header: 'Grade', path: 'Grade__c', type: 'text' },
  { key: 'segment', header: 'Segment', path: 'Segment__c', type: 'text' },
  { key: 'leadAuthor', header: 'Lead author', path: 'Lead_Author__r.Name', type: 'text' },
  { key: 'closer', header: 'Closer', path: 'Closer__r.Name', type: 'text' },
  { key: 'keyCallBookedOn', header: 'Key call booked on', path: 'Key_Call_Booked_On__c', type: 'date' },
  { key: 'keyCallAt', header: 'Key call date and time', path: 'Key_Call_At__c', type: 'datetime' },
  { key: 'keyCallOutcome', header: 'Key call outcome', path: 'Key_Call_Outcome__c', type: 'text' },
  { key: 'keyCallResult', header: 'Key call result', path: 'Key_Call_Result__c', type: 'text' },
  { key: 'objection', header: 'Objection', path: 'Objection__c', type: 'text' },
  { key: 'prepaymentDate', header: 'Prepayment date', path: 'Prepayment_Date__c', type: 'date' },
  { key: 'paymentMethod', header: 'Payment method', path: 'Payment_Method__c', type: 'text' },
  { key: 'fullPaymentDate', header: 'Full payment date', path: 'Full_Payment_Date__c', type: 'date' },
  { key: 'amount', header: 'Amount', path: 'Amount', type: 'number' },
  { key: 'startPeriod', header: 'Start period', path: 'Start_Period__c', type: 'text' },
  { key: 'refusalReason', header: 'Refusal reason', path: 'Refusal_Reason__c', type: 'text' },
  { key: 'refusalType', header: 'Refusal type', path: 'Refusal_Type__c', type: 'text' },
  { key: 'firstResponse', header: 'First response time', path: 'First_Response_At__c', type: 'datetime' },
  { key: 'lastActivity', header: 'Last activity date', path: 'LastActivityDate', type: 'date' },
  { key: 'closeDate', header: 'Close date', path: 'CloseDate', type: 'date', onlyWhen: 'IsClosed' }
];

/** Reads a field, following relationships such as "Closer__r.Name". Missing parts give null. */
function fieldValue(record, path) {
  return path.split('.').reduce(function (value, part) {
    return value === null || value === undefined ? null : value[part];
  }, record);
}

/** "2026-10-05" as a local date (no time zone shift in the sheet). */
function parseDate(text) {
  var parts = String(text).split('-');
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
}

/** "2026-10-05T09:30:00.000+0000" as an instant. Salesforce writes the offset without a colon. */
function parseDateTime(text) {
  return new Date(String(text).replace(/([+-]\d{2})(\d{2})$/, '$1:$2'));
}

function toCell(value, type) {
  if (value === null || value === undefined || value === '') {
    return '';
  }
  if (type === 'date') {
    return parseDate(value);
  }
  if (type === 'datetime') {
    return parseDateTime(value);
  }
  if (type === 'number') {
    return Number(value);
  }
  return String(value);
}

/** One deal, one row (EX3). The close date only counts once the deal is closed. */
function rowFromRecord(record) {
  return COLUMNS.map(function (column) {
    if (column.onlyWhen && !record[column.onlyWhen]) {
      return '';
    }
    return toCell(fieldValue(record, column.path), column.type);
  });
}

/** The whole Raw sheet: the header row, then one row per deal. */
function rowsFromRecords(records) {
  var header = COLUMNS.map(function (column) {
    return column.header;
  });
  return [header].concat(records.map(rowFromRecord));
}

/** Column letter of a Raw column: "A" for the first. */
function columnLetter(index) {
  var letters = '';
  for (var n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) {
    letters = String.fromCharCode(65 + ((n - 1) % 26)) + letters;
  }
  return letters;
}

function columnIndex(key) {
  for (var i = 0; i < COLUMNS.length; i++) {
    if (COLUMNS[i].key === key) {
      return i;
    }
  }
  throw new Error('No Raw column called ' + key);
}

function rawRange(key) {
  var letter = columnLetter(columnIndex(key));
  return RAW_SHEET + '!$' + letter + ':$' + letter;
}

/** A text value inside a formula, with its quotes doubled. */
function quoted(text) {
  return '"' + String(text).replace(/"/g, '""') + '"';
}

// ---- Dashboard (EX4) -------------------------------------------------------------------------

var MONTH_CELL = '$B$2';
var LIST_ROWS = 12; // room for the names a list block can show (closers, sources, periods...)

/**
 * A criterion is [column key, operator, value]:
 *   'is'      equals a text (lists add the row's name automatically)
 *   'blank'   empty                 'filled'  not empty
 *   'inMonth' a date in the month shown in the Month cell
 *   'olderThanMinutes' a date-time more than that many minutes ago
 */
function criteriaArgs(criteria) {
  var args = [];
  criteria.forEach(function (criterion) {
    var range = rawRange(criterion[0]);
    var op = criterion[1];
    if (op === 'is') {
      args.push(range, typeof criterion[2] === 'object' ? criterion[2].cell : quoted(criterion[2]));
    } else if (op === 'blank') {
      args.push(range, '""');
    } else if (op === 'filled') {
      args.push(range, '"<>"');
    } else if (op === 'inMonth') {
      args.push(range, '">="&' + MONTH_CELL, range, '"<"&EDATE(' + MONTH_CELL + ',1)');
    } else if (op === 'olderThanMinutes') {
      args.push(range, '"<"&(NOW()-' + criterion[2] + '/1440)');
    } else {
      throw new Error('Unknown operator ' + op);
    }
  });
  return args;
}

function countExpression(criteria) {
  return 'COUNTIFS(' + criteriaArgs(criteria).join(',') + ')';
}

function sumExpression(key, criteria) {
  return 'SUMIFS(' + rawRange(key) + ',' + criteriaArgs(criteria).join(',') + ')';
}

/** The eight blocks of the brief. Rows blocks list metrics; list blocks show one row per name. */
function dashboardBlocks() {
  var month = ['created', 'inMonth'];
  return [
    { title: '1. Funnel of the month (deals created in the month)', rows: [
      { label: 'New deals', count: [month] },
      { label: 'First response given', count: [month, ['firstResponse', 'filled']] },
      { label: 'Key call booked', count: [month, ['keyCallBookedOn', 'filled']] },
      { label: 'Key call held', count: [month, ['keyCallOutcome', 'is', 'Held']] },
      { label: 'Prepayment received', count: [month, ['prepaymentDate', 'filled']] },
      { label: 'Paid in full', count: [month, ['fullPaymentDate', 'filled']] }
    ] },
    { title: '2. Conversion rates (same deals)', rows: [
      { label: 'Lead to key call booked', ratio: ['Key call booked', 'New deals'] },
      { label: 'Key call booked to held', ratio: ['Key call held', 'Key call booked'] },
      { label: 'Key call held to prepayment', ratio: ['Prepayment received', 'Key call held'] },
      { label: 'Prepayment to full payment', ratio: ['Paid in full', 'Prepayment received'] },
      { label: 'Lead to full payment', ratio: ['Paid in full', 'New deals'] }
    ] },
    { title: '3. By closer (key calls booked in the month)', listOf: 'closer', header: 'Closer', columns: [
      { header: 'Calls booked', count: [['keyCallBookedOn', 'inMonth']] },
      { header: 'Calls held', count: [['keyCallBookedOn', 'inMonth'], ['keyCallOutcome', 'is', 'Held']] },
      { header: 'Purchases', count: [['keyCallBookedOn', 'inMonth'], ['keyCallResult', 'is', 'Purchase']] },
      { header: 'Prepayments', count: [['prepaymentDate', 'inMonth']] },
      { header: 'Revenue', sum: 'amount', where: [['fullPaymentDate', 'inMonth']] }
    ] },
    { title: '4. By chat manager (leads created in the month)', listOf: 'leadAuthor', header: 'Chat manager', columns: [
      { header: 'Leads', count: [month] },
      { header: 'Answered', count: [month, ['firstResponse', 'filled']] },
      { header: 'Key calls booked', count: [month, ['keyCallBookedOn', 'filled']] },
      { header: 'Prepayments', count: [month, ['prepaymentDate', 'filled']] }
    ] },
    { title: '5. Unprocessed leads (right now)', rows: [
      { label: 'New leads with no reply yet', count: [['stage', 'is', 'New lead'], ['firstResponse', 'blank']] },
      { label: 'of which waiting over 30 minutes',
        count: [['stage', 'is', 'New lead'], ['firstResponse', 'blank'], ['created', 'olderThanMinutes', 30]] }
    ] },
    { title: '6. Enrollment forecast by start period', listOf: 'startPeriod', header: 'Start period', columns: [
      { header: 'Prepaid, not yet in full', count: [['prepaymentDate', 'filled'], ['fullPaymentDate', 'blank']] },
      { header: 'Paid in full', count: [['fullPaymentDate', 'filled']] },
      { header: 'Amount paid in full', sum: 'amount', where: [['fullPaymentDate', 'filled']] },
      { header: 'Expected students', plus: ['Prepaid, not yet in full', 'Paid in full'] }
    ] },
    { title: '7. Sources with CPL and CAC (month; ad spend from the Ad spend sheet)', listOf: 'source', header: 'Source', columns: [
      { header: 'Leads', count: [month] },
      { header: 'Customers', count: [['fullPaymentDate', 'inMonth']] },
      { header: 'Ad spend', adSpend: true },
      { header: 'CPL', divide: ['Ad spend', 'Leads'] },
      { header: 'CAC', divide: ['Ad spend', 'Customers'] }
    ] },
    { title: '8. Refusal reasons (all deals with a reason)', listOf: 'refusalReason', header: 'Refusal reason', columns: [
      { header: 'Deals', count: [] },
      { header: 'Share', share: 'Deals' }
    ] }
  ];
}

/** The Dashboard sheet as cells: {row, col, value, bold, format}. Rows and columns start at 1. */
function dashboardCells() {
  var cells = [];
  var rowOf = {}; // metric label -> row, so conversion rates can point at the funnel
  function put(row, col, value, extra) {
    var cell = { row: row, col: col, value: value };
    Object.keys(extra || {}).forEach(function (key) {
      cell[key] = extra[key];
    });
    cells.push(cell);
  }
  put(1, 1, 'Sales dashboard', { bold: true });
  put(1, 2, 'Formulas over the Raw sheet. Nothing here is typed by hand; ad spend goes in the Ad spend sheet.');
  put(2, 1, 'Month', { bold: true });
  put(2, 2, '=DATE(YEAR(TODAY()),MONTH(TODAY()),1)', { format: 'mmmm yyyy' });
  var row = 4;
  dashboardBlocks().forEach(function (block) {
    put(row, 1, block.title, { bold: true });
    row = block.rows ? renderRows(block, row + 1, put, rowOf) : renderList(block, row + 1, put);
    row += 1;
  });
  return cells;
}

function renderRows(block, row, put, rowOf) {
  block.rows.forEach(function (metric) {
    put(row, 1, metric.label);
    if (metric.count) {
      put(row, 2, '=' + countExpression(metric.count));
    } else {
      put(row, 2, '=IFERROR(B' + rowOf[metric.ratio[0]] + '/B' + rowOf[metric.ratio[1]] + ',"")', { format: '0%' });
    }
    rowOf[metric.label] = row;
    row += 1;
  });
  return row;
}

function renderList(block, row, put) {
  var key = block.listOf;
  var raw = RAW_SHEET + '!$' + columnLetter(columnIndex(key));
  var colOf = {};
  put(row, 1, block.header, { bold: true });
  block.columns.forEach(function (column, i) {
    colOf[column.header] = columnLetter(i + 1);
    put(row, i + 2, column.header, { bold: true });
  });
  var first = row + 1;
  var last = first + LIST_ROWS - 1;
  put(first, 1, '=SORT(UNIQUE(FILTER(' + raw + '$2:' + raw.split('!')[1] + ',' + raw + '$2:' + raw.split('!')[1] + '<>"")))');
  for (var r = first; r <= last; r++) {
    block.columns.forEach(function (column, i) {
      var format = column.share ? { format: '0%' } : column.divide ? { format: '0.00' } : {};
      put(r, i + 2, '=IF($A' + r + '="","",' + columnExpression(column, key, r, colOf, first, last) + ')', format);
    });
  }
  return last + 1;
}

function columnExpression(column, key, r, colOf, first, last) {
  var byName = [[key, 'is', { cell: '$A' + r }]];
  if (column.count) {
    return countExpression(byName.concat(column.count));
  }
  if (column.sum) {
    return sumExpression(column.sum, byName.concat(column.where));
  }
  if (column.adSpend) {
    var sheet = "'" + AD_SPEND_SHEET + "'!";
    return 'SUMIFS(' + sheet + '$C:$C,' + sheet + '$A:$A,' + MONTH_CELL + ',' + sheet + '$B:$B,$A' + r + ')';
  }
  if (column.divide) {
    var top = colOf[column.divide[0]] + r;
    var bottom = colOf[column.divide[1]] + r;
    return 'IF(OR(' + top + '=0,' + bottom + '=0),"",' + top + '/' + bottom + ')';
  }
  if (column.plus) {
    return colOf[column.plus[0]] + r + '+' + colOf[column.plus[1]] + r;
  }
  if (column.share) {
    var c = colOf[column.share];
    return 'IFERROR(' + c + r + '/SUM(' + c + '$' + first + ':' + c + '$' + last + '),"")';
  }
  throw new Error('Unknown dashboard column ' + column.header);
}

// ---- What the formulas count, in plain JavaScript (used by the tests) -----------------------

function matches(row, criterion, context) {
  var value = row[columnIndex(criterion[0])];
  var empty = value === '' || value === null || value === undefined;
  var op = criterion[1];
  if (op === 'is') {
    var wanted = typeof criterion[2] === 'object' ? context.name : criterion[2];
    return !empty && String(value).toLowerCase() === String(wanted).toLowerCase();
  }
  if (op === 'blank') {
    return empty;
  }
  if (op === 'filled') {
    return !empty;
  }
  if (op === 'inMonth') {
    var start = context.month;
    var end = new Date(start.getFullYear(), start.getMonth() + 1, 1);
    return value instanceof Date && value >= start && value < end;
  }
  if (op === 'olderThanMinutes') {
    return value instanceof Date && value.getTime() < context.now.getTime() - criterion[2] * 60000;
  }
  throw new Error('Unknown operator ' + op);
}

function countRows(rows, criteria, context) {
  return rows.filter(function (row) {
    return criteria.every(function (criterion) {
      return matches(row, criterion, context);
    });
  }).length;
}

function sumRows(rows, key, criteria, context) {
  return rows.reduce(function (total, row) {
    var keep = criteria.every(function (criterion) {
      return matches(row, criterion, context);
    });
    return keep ? total + Number(row[columnIndex(key)] || 0) : total;
  }, 0);
}

/** The names a list block shows, as SORT(UNIQUE(FILTER(...))) would. */
function listNames(rows, key) {
  var seen = {};
  rows.forEach(function (row) {
    var value = row[columnIndex(key)];
    if (value !== '' && value !== null && value !== undefined) {
      seen[String(value)] = true;
    }
  });
  return Object.keys(seen).sort(function (a, b) {
    return a.toLowerCase() < b.toLowerCase() ? -1 : a.toLowerCase() > b.toLowerCase() ? 1 : 0;
  });
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    RAW_SHEET: RAW_SHEET, DASHBOARD_SHEET: DASHBOARD_SHEET, AD_SPEND_SHEET: AD_SPEND_SHEET,
    AD_SPEND_HEADER: AD_SPEND_HEADER, EXPORT_SOQL: EXPORT_SOQL, COLUMNS: COLUMNS, LIST_ROWS: LIST_ROWS,
    fieldValue: fieldValue, parseDate: parseDate, parseDateTime: parseDateTime, rowFromRecord: rowFromRecord,
    rowsFromRecords: rowsFromRecords, columnLetter: columnLetter, rawRange: rawRange, quoted: quoted,
    criteriaArgs: criteriaArgs, countExpression: countExpression, sumExpression: sumExpression,
    dashboardBlocks: dashboardBlocks, dashboardCells: dashboardCells, countRows: countRows, sumRows: sumRows,
    listNames: listNames
  };
}
