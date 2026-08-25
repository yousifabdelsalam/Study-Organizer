import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class DatabaseHelper {
  static Database? _db;
  static final DatabaseHelper instance = DatabaseHelper._();
  DatabaseHelper._();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<String> get dbPath async {
    return p.join(await getDatabasesPath(), 'eng_org_v5.db');
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  Future<Database> _init() async {
    final path = await dbPath;
    return openDatabase(
      path,
      version: 16,
      onCreate: (db, v) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 16) {
          try {
            await db.execute(
              "ALTER TABLE jarvis_documents ADD COLUMN fileUri TEXT",
            );
          } catch (_) {}
          try {
            await db.execute(
              "ALTER TABLE jarvis_documents ADD COLUMN fileMime TEXT",
            );
          } catch (_) {}
        }
        if (oldV < 15) {
          try {
            await db.execute(
              "ALTER TABLE timetable ADD COLUMN isExceptional INTEGER DEFAULT 0",
            );
          } catch (_) {}
          try {
            await db.execute(
              "ALTER TABLE timetable ADD COLUMN exceptionalDate TEXT DEFAULT ''",
            );
          } catch (_) {}
        }
        if (oldV < 14) {
          try {
            await db.execute(
              "ALTER TABLE tasks ADD COLUMN isFailed INTEGER DEFAULT 0",
            );
          } catch (_) {}
        }
        if (oldV < 13) {
          // ── NOVA Phase 2-4 tables ────────────────────────────────────────
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS nova_subject_intel(
              subjectId   INTEGER PRIMARY KEY,
              subjectName TEXT NOT NULL,
              cardText    TEXT NOT NULL,
              documentCount INTEGER DEFAULT 0,
              updatedAt   TEXT,
              FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
            )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS nova_study_plan(
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              subjectId   INTEGER,
              dayOfWeek   INTEGER NOT NULL,
              date        TEXT NOT NULL,
              startTime   TEXT NOT NULL,
              endTime     TEXT NOT NULL,
              topicTitle  TEXT NOT NULL,
              reason      TEXT DEFAULT '',
              status      TEXT DEFAULT 'pending',
              weekNumber  INTEGER DEFAULT 0,
              FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
            )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS nova_daily_schedule(
              id          INTEGER PRIMARY KEY AUTOINCREMENT,
              dayOfWeek   INTEGER NOT NULL,
              slotHour    INTEGER NOT NULL,
              slotMinute  INTEGER NOT NULL,
              label       TEXT NOT NULL,
              isOverride  INTEGER DEFAULT 0,
              overrideDate TEXT
            )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS nova_watchdog_apps(
              package     TEXT PRIMARY KEY,
              displayName TEXT NOT NULL,
              limitMinutes INTEGER NOT NULL DEFAULT 30
            )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS nova_weekly_briefing(
              weekNumber  INTEGER PRIMARY KEY,
              briefingText TEXT NOT NULL,
              createdAt   TEXT
            )''');
          } catch (_) {}
        }
        if (oldV < 12) {
          try {
            await db.execute(
              "ALTER TABLE topics ADD COLUMN prerequisites TEXT DEFAULT '[]'",
            );
          } catch (_) {}
        }
        if (oldV < 11) {
          try {
            await db.execute("ALTER TABLE marks ADD COLUMN lossReason TEXT");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE marks ADD COLUMN createdAt TEXT");
          } catch (_) {}
        }
        if (oldV < 10) {
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS pomodoro_sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER,
            topicLabel TEXT,
            mode TEXT DEFAULT 'focus',
            startedAt TEXT NOT NULL,
            endedAt TEXT,
            plannedSeconds INTEGER DEFAULT 0,
            actualSeconds INTEGER DEFAULT 0,
            completed INTEGER DEFAULT 0,
            notes TEXT,
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE SET NULL
          )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS jarvis_chat_rooms(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            messages TEXT NOT NULL DEFAULT '[]',
            createdAt TEXT
          )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE IF NOT EXISTS jarvis_doc_analysis(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER NOT NULL,
            docId INTEGER NOT NULL,
            analysis TEXT NOT NULL,
            createdAt TEXT,
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
          )''');
          } catch (_) {}
        }
        if (oldV < 8) {
          try {
            await db.execute('''CREATE TABLE jarvis_documents(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER NOT NULL,
            type TEXT NOT NULL,
            name TEXT NOT NULL,
            content TEXT NOT NULL,
            createdAt TEXT,
            fileUri TEXT,
            fileMime TEXT,
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
          )''');
          } catch (_) {}
          try {
            await db.execute('''CREATE TABLE subject_metadata(
            subjectId INTEGER PRIMARY KEY,
            instructor_focus TEXT DEFAULT '',
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
          )''');
          } catch (_) {}
        }
        if (oldV < 5) {
          try {
            await db.execute('''CREATE TABLE topics(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER,
            title TEXT NOT NULL,
            stage INTEGER DEFAULT 0,
            lastStudied TEXT,
            nextReview TEXT,
            notes TEXT DEFAULT '',
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
          )''');
          } catch (_) {}
        }
        if (oldV < 6) {
          // Add notes column to topics if upgrading
          try {
            await db.execute(
              "ALTER TABLE topics ADD COLUMN notes TEXT DEFAULT ''",
            );
          } catch (_) {}
          // Create subject_notes table
          try {
            await db.execute('''CREATE TABLE subject_notes(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            subjectId INTEGER,
            category TEXT DEFAULT 'General',
            title TEXT NOT NULL,
            content TEXT DEFAULT '',
            createdAt TEXT,
            updatedAt TEXT,
            FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
          )''');
          } catch (_) {}
        }
        if (oldV < 7) {
          try {
            await db.execute(
              "ALTER TABLE tasks ADD COLUMN isWorking INTEGER DEFAULT 0",
            );
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS subjects(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, doctorName TEXT, sectionEngineer TEXT, labEngineer TEXT,
      color INTEGER DEFAULT 4285550863, creditHours INTEGER DEFAULT 3,
      maxLectureAbs INTEGER DEFAULT 4, maxSectionAbs INTEGER DEFAULT 4,
      maxLabAbs INTEGER DEFAULT 4, hasSection INTEGER DEFAULT 1, hasLab INTEGER DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS tasks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER, title TEXT NOT NULL, description TEXT,
      dueDate TEXT, priority INTEGER DEFAULT 2, isCompleted INTEGER DEFAULT 0,
      type TEXT DEFAULT 'assignment', createdAt TEXT, completedAt TEXT,
      isWorking INTEGER DEFAULT 0,
      isFailed INTEGER DEFAULT 0,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS absences(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER, date TEXT, type TEXT DEFAULT 'lecture',
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS marks(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER, category TEXT, label TEXT,
      obtained REAL DEFAULT 0, total REAL DEFAULT 0,
      lossReason TEXT, createdAt TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS semesters(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT, gpa REAL, credits INTEGER, createdAt TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS timetable(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER, dayOfWeek INTEGER, startTime TEXT, endTime TEXT,
      type TEXT DEFAULT 'lecture', room TEXT DEFAULT '', building TEXT DEFAULT '',
      weekType TEXT DEFAULT 'both',
      isExceptional INTEGER DEFAULT 0,
      exceptionalDate TEXT DEFAULT '',
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS reminders(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL, date TEXT NOT NULL, time TEXT DEFAULT '08:00', isDone INTEGER DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS topics(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER, title TEXT NOT NULL, stage INTEGER DEFAULT 0,
      lastStudied TEXT, nextReview TEXT, notes TEXT DEFAULT '', prerequisites TEXT DEFAULT '[]',
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS subject_notes(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER,
      category TEXT DEFAULT 'General',
      title TEXT NOT NULL,
      content TEXT DEFAULT '',
      createdAt TEXT,
      updatedAt TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS jarvis_documents(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER NOT NULL,
      type TEXT NOT NULL,
      name TEXT NOT NULL,
      content TEXT NOT NULL,
      createdAt TEXT,
      fileUri TEXT,
      fileMime TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS subject_metadata(
      subjectId INTEGER PRIMARY KEY,
      instructor_focus TEXT DEFAULT '',
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS jarvis_chat_rooms(
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      messages TEXT NOT NULL DEFAULT '[]',
      createdAt TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS jarvis_doc_analysis(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER NOT NULL,
      docId INTEGER NOT NULL,
      analysis TEXT NOT NULL,
      createdAt TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');

    // ── NOVA tables ──────────────────────────────────────────────────────────
    await db.execute('''CREATE TABLE IF NOT EXISTS nova_subject_intel(
      subjectId   INTEGER PRIMARY KEY,
      subjectName TEXT NOT NULL,
      cardText    TEXT NOT NULL,
      documentCount INTEGER DEFAULT 0,
      updatedAt   TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS nova_study_plan(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId  INTEGER,
      dayOfWeek  INTEGER NOT NULL,
      date       TEXT NOT NULL,
      startTime  TEXT NOT NULL,
      endTime    TEXT NOT NULL,
      topicTitle TEXT NOT NULL,
      reason     TEXT DEFAULT '',
      status     TEXT DEFAULT 'pending',
      weekNumber INTEGER DEFAULT 0,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE CASCADE
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS nova_daily_schedule(
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      dayOfWeek  INTEGER NOT NULL,
      slotHour   INTEGER NOT NULL,
      slotMinute INTEGER NOT NULL,
      label      TEXT NOT NULL,
      isOverride INTEGER DEFAULT 0,
      overrideDate TEXT
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS nova_watchdog_apps(
      package     TEXT PRIMARY KEY,
      displayName TEXT NOT NULL,
      limitMinutes INTEGER NOT NULL DEFAULT 30
    )''');
    await db.execute('''CREATE TABLE IF NOT EXISTS nova_weekly_briefing(
      weekNumber  INTEGER PRIMARY KEY,
      briefingText TEXT NOT NULL,
      createdAt   TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS pomodoro_sessions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      subjectId INTEGER,
      topicLabel TEXT,
      mode TEXT DEFAULT 'focus',
      startedAt TEXT NOT NULL,
      endedAt TEXT,
      plannedSeconds INTEGER DEFAULT 0,
      actualSeconds INTEGER DEFAULT 0,
      completed INTEGER DEFAULT 0,
      notes TEXT,
      FOREIGN KEY(subjectId) REFERENCES subjects(id) ON DELETE SET NULL
    )''');
  }

  // ── Pomodoro Session CRUD ─────────────────────────────────────────────────
  Future<int> insertPomodoroSession(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('pomodoro_sessions', data);
  }

  Future<void> updatePomodoroSession(int id, Map<String, dynamic> data) async {
    final db = await database;
    await db.update(
      'pomodoro_sessions',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getPomodoroSessions({
    int? subjectId,
    int limit = 100,
  }) async {
    final db = await database;
    if (subjectId != null) {
      return db.query(
        'pomodoro_sessions',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
        orderBy: 'startedAt DESC',
        limit: limit,
      );
    }
    return db.query(
      'pomodoro_sessions',
      orderBy: 'startedAt DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getPomodoroSessionsSince(
    DateTime since,
  ) async {
    final db = await database;
    return db.query(
      'pomodoro_sessions',
      where: 'startedAt >= ?',
      whereArgs: [since.toIso8601String()],
      orderBy: 'startedAt DESC',
    );
  }

  Future<void> deletePomodoroSession(int id) async {
    final db = await database;
    await db.delete('pomodoro_sessions', where: 'id = ?', whereArgs: [id]);
  }
}
