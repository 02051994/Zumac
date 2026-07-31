import 'dart:math' as math;

class FormulaEngine {
  final List<Map<String, dynamic>> fields;
  final Map<String, List<Map<String, dynamic>>> matrixRowsByTable;
  final dynamic Function(String campo) getValue;

  FormulaEngine({
    required this.fields,
    required this.matrixRowsByTable,
    required this.getValue,
  });

  String evaluateToText(String formula) {
    final value = evaluate(formula);
    if (value == null) return '';
    if (value is num) return _formatNumber(value.toDouble());
    return value.toString();
  }

  dynamic evaluate(String formula) {
    final expr = formula.trim();
    if (expr.isEmpty) return '';
    return _evalExpression(expr);
  }

  bool evaluateCondition(String formula) {
    final expr = formula.trim();
    if (expr.isEmpty) return true;
    return _evalCondition(expr);
  }

  dynamic _evalExpression(String expr) {
    expr = expr.trim();
    if (expr.isEmpty) return '';
    if (_isQuoted(expr)) return _unquote(expr);
    final upperLiteral = expr.toUpperCase();
    if (upperLiteral == 'TRUE' || upperLiteral == 'VERDADERO') return true;
    if (upperLiteral == 'FALSE' || upperLiteral == 'FALSO') return false;
    if (_isFieldRef(expr)) return _resolveField(expr);
    if (_isDateLiteral(expr)) return expr;

    // Primero reconocer números puros. Antes, valores como "10000 - 1000"
    // podían entrar por _isPlainIdentifier porque ese regex aceptaba guiones,
    // y la fórmula terminaba mostrándose como texto en vez de calcularse.
    if (_isNumericLiteral(expr)) return _toDouble(expr);

    final directFunction = _readDirectFunction(expr);
    if (directFunction != null && directFunction.end == expr.length) {
      return _evalFunction(directFunction.name, directFunction.args);
    }

    // Si la expresión contiene operadores o llamadas de función, SIEMPRE debe
    // pasar por el evaluador matemático. Esto cubre:
    // 10000 - 1000
    // 200 * 100
    // 0.20 * NUM([CANT(JABAS)])
    // NUM([uuid]) - NUM([uuid])
    if (_looksLikeMathExpression(expr)) {
      final replacedFieldsFirst = _replaceFieldReferencesForMath(expr);
      final replacedFunctions = _replaceFunctionCalls(replacedFieldsFirst);
      final numeric = _ExpressionParser(replacedFunctions).parse();
      if (numeric.isNaN || numeric.isInfinite) return '';
      return numeric;
    }

    if (_isPlainIdentifier(expr)) {
      final field = _fieldByIdentifier(expr);
      if (field != null) return _resolveField(expr);
      // Permite comparar textos sin comillas en condiciones simples:
      // IF([TIPO] = Exportable; 1; 0)
      return expr;
    }

    final replacedFieldsFirst = _replaceFieldReferencesForMath(expr);
    final replacedFunctions = _replaceFunctionCalls(replacedFieldsFirst);
    final numeric = _ExpressionParser(replacedFunctions).parse();
    if (numeric.isNaN || numeric.isInfinite) return '';
    return numeric;
  }

  String _replaceFunctionCalls(String expr) {
    var current = expr;
    while (true) {
      final call = _findFirstFunctionCall(current);
      if (call == null) return current;
      final value = _evalFunction(call.name, call.args);
      final replacement = value is num
          ? value.toString()
          : (double.tryParse(value?.toString().trim().replaceAll(',', '.') ?? '')?.toString() ?? '0');
      current = current.substring(0, call.start) + replacement + current.substring(call.end);
    }
  }

  _FunctionCall? _findFirstFunctionCall(String expr) {
    var inString = false;
    String? quote;
    var squareLevel = 0;
    var braceLevel = 0;

    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if ((c == "'" || c == '"')) {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;

      if (c == '[') {
        squareLevel++;
        continue;
      }
      if (c == ']' && squareLevel > 0) {
        squareLevel--;
        continue;
      }
      if (c == '{' && i + 1 < expr.length && expr[i + 1] == '{') {
        braceLevel++;
        i++;
        continue;
      }
      if (c == '}' && i + 1 < expr.length && expr[i + 1] == '}' && braceLevel > 0) {
        braceLevel--;
        i++;
        continue;
      }
      if (squareLevel > 0 || braceLevel > 0) continue;
      if (c != '(') continue;

      var j = i - 1;
      while (j >= 0 && RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_.]').hasMatch(expr[j])) {
        j--;
      }
      final name = expr.substring(j + 1, i).trim();
      if (name.isEmpty) continue;
      final close = _findClosingParen(expr, i);
      if (close == -1) continue;
      final rawArgs = expr.substring(i + 1, close);
      return _FunctionCall(name: name, args: _splitArgs(rawArgs), start: j + 1, end: close + 1);
    }
    return null;
  }

  bool _isNumericLiteral(String value) {
    final text = value.trim().replaceAll(',', '.');
    return RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(text);
  }

  bool _looksLikeMathExpression(String expr) {
    var inString = false;
    String? quote;
    var squareLevel = 0;
    var braceLevel = 0;
    var parenLevel = 0;

    for (var i = 0; i < expr.length; i++) {
      final c = expr[i];
      if (c == "'" || c == '"') {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;

      if (c == '[') {
        squareLevel++;
        continue;
      }
      if (c == ']' && squareLevel > 0) {
        squareLevel--;
        continue;
      }
      if (c == '{' && i + 1 < expr.length && expr[i + 1] == '{') {
        braceLevel++;
        i++;
        continue;
      }
      if (c == '}' && i + 1 < expr.length && expr[i + 1] == '}' && braceLevel > 0) {
        braceLevel--;
        i++;
        continue;
      }
      if (squareLevel > 0 || braceLevel > 0) continue;

      if (c == '(') {
        // Una palabra seguida de paréntesis es llamada de función y puede
        // formar parte de una expresión matemática: 0.20 * NUM(...).
        var j = i - 1;
        while (j >= 0 && expr[j].trim().isEmpty) {
          j--;
        }
        while (j >= 0 && RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_.]').hasMatch(expr[j])) {
          j--;
        }
        final name = expr.substring(j + 1, i).trim();
        if (name.isNotEmpty) return true;
        parenLevel++;
        continue;
      }
      if (c == ')' && parenLevel > 0) {
        parenLevel--;
        continue;
      }

      if ('*/+'.contains(c) || c == '√') return true;
      if (c == '-') {
        // Considerar '-' operador solo si no es signo inicial de número.
        final prev = i > 0 ? expr[i - 1] : '';
        final next = i + 1 < expr.length ? expr[i + 1] : '';
        if (i > 0 && next.isNotEmpty && (RegExp(r'\d|\s|\[').hasMatch(prev) || prev == ')')) return true;
      }
    }
    return false;
  }

  _FunctionCall? _readDirectFunction(String expr) {
    final match = RegExp(r'^([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_.]+)\s*\(').firstMatch(expr);
    if (match == null) return null;
    final open = expr.indexOf('(', match.end - 1);
    final close = _findClosingParen(expr, open);
    if (close == -1) return null;
    return _FunctionCall(
      name: match.group(1) ?? '',
      args: _splitArgs(expr.substring(open + 1, close)),
      start: 0,
      end: close + 1,
    );
  }

  int _findClosingParen(String expr, int openIndex) {
    var level = 0;
    var inString = false;
    String? quote;
    var squareLevel = 0;
    var braceLevel = 0;

    for (var i = openIndex; i < expr.length; i++) {
      final c = expr[i];
      if ((c == "'" || c == '"')) {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;

      if (c == '[') {
        squareLevel++;
        continue;
      }
      if (c == ']' && squareLevel > 0) {
        squareLevel--;
        continue;
      }
      if (c == '{' && i + 1 < expr.length && expr[i + 1] == '{') {
        braceLevel++;
        i++;
        continue;
      }
      if (c == '}' && i + 1 < expr.length && expr[i + 1] == '}' && braceLevel > 0) {
        braceLevel--;
        i++;
        continue;
      }
      if (squareLevel > 0 || braceLevel > 0) continue;

      if (c == '(') level++;
      if (c == ')') {
        level--;
        if (level == 0) return i;
      }
    }
    return -1;
  }

  List<String> _splitArgs(String raw) {
    final args = <String>[];
    var level = 0;
    var inString = false;
    String? quote;
    var squareLevel = 0;
    var braceLevel = 0;
    final buffer = StringBuffer();

    for (var i = 0; i < raw.length; i++) {
      final c = raw[i];
      if ((c == "'" || c == '"')) {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (!inString) {
        if (c == '[') squareLevel++;
        if (c == ']' && squareLevel > 0) squareLevel--;
        if (c == '{' && i + 1 < raw.length && raw[i + 1] == '{') {
          braceLevel++;
          buffer.write(c);
          i++;
          buffer.write(raw[i]);
          continue;
        }
        if (c == '}' && i + 1 < raw.length && raw[i + 1] == '}' && braceLevel > 0) {
          braceLevel--;
          buffer.write(c);
          i++;
          buffer.write(raw[i]);
          continue;
        }
        if (squareLevel == 0 && braceLevel == 0) {
          if (c == '(') level++;
          if (c == ')') level--;
          if ((c == ',' || c == ';') && level == 0) {
            args.add(buffer.toString().trim());
            buffer.clear();
            continue;
          }
        }
      }
      buffer.write(c);
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) args.add(last);
    return args;
  }

  dynamic _evalFunction(String rawName, List<String> args) {
    final name = _normalizeFunction(rawName);

    switch (name) {
      case 'SUMA':
        return _values(args).fold<double>(0, (a, b) => a + _toDouble(b));
      case 'RESTA':
        final rawValues = _values(args);
        if (rawValues.length >= 2) {
          final firstDate = _tryParseFormulaDate(rawValues[0]);
          final secondDate = _tryParseFormulaDate(rawValues[1]);
          if (firstDate != null && secondDate != null) {
            return _dateOnly(firstDate).difference(_dateOnly(secondDate)).inDays;
          }
        }
        final values = rawValues.map(_toDouble).toList();
        if (values.isEmpty) return 0;
        return values.skip(1).fold<double>(values.first, (a, b) => a - b);
      case 'RESTA_TIEMPOS':
        if (args.length < 2) return '';
        final start = _timeMinutesFromArg(args[0]);
        final end = _timeMinutesFromArg(args[1]);
        if (start == null || end == null) return '';
        var diff = end - start;
        if (diff < 0) diff += 24 * 60;
        return _formatDuration(diff);
      case 'FECHAS_TRANSCURRIDAS':
        if (args.length < 2) return '';
        final startDate = _tryParseFormulaDate(_evalExpression(args[0]));
        final endDate = _tryParseFormulaDate(_evalExpression(args[1]));
        if (startDate == null || endDate == null) return '';
        return _dateOnly(endDate).difference(_dateOnly(startDate)).inDays;
      case 'SUMAR_DIAS':
        if (args.length < 2) return '';
        final baseDate = _tryParseFormulaDate(_evalExpression(args[0]));
        if (baseDate == null) return '';
        final days = _toDouble(_evalExpression(args[1])).round();
        return _formatFormulaDate(_dateOnly(baseDate).add(Duration(days: days)));
      case 'HORA_ACTUAL':
      case 'AHORA_HORA':
        return _formatFormulaTime(DateTime.now());
      case 'FECHA_ACTUAL':
      case 'HOY':
        return _formatFormulaDate(DateTime.now());
      case 'FECHA_HORA_ACTUAL':
      case 'FECHAHORA_ACTUAL':
      case 'AHORA':
        return _formatFormulaDateTime(DateTime.now());
      case 'MULTIPLICACION':
        final values = _values(args).map(_toDouble).toList();
        if (values.isEmpty) return 0;
        return values.fold<double>(1, (a, b) => a * b);
      case 'DIVISION':
        final values = _values(args).map(_toDouble).toList();
        if (values.length < 2) return '';
        return values.skip(1).fold<double>(values.first, (a, b) => b == 0 ? double.nan : a / b);
      case 'PROMEDIO':
        final nums = _values(args).map(_toDouble).toList();
        if (nums.isEmpty) return 0;
        return nums.reduce((a, b) => a + b) / nums.length;
      case 'RAIZ':
        final value = _toDouble(_evalExpression(args.isEmpty ? '0' : args.first));
        return value < 0 ? double.nan : math.sqrt(value);
      case 'MAXIMO':
        final nums = _values(args).map(_toDouble).toList();
        return nums.isEmpty ? 0 : nums.reduce((a, b) => math.max(a, b).toDouble());
      case 'MINIMO':
        final nums = _values(args).map(_toDouble).toList();
        return nums.isEmpty ? 0 : nums.reduce((a, b) => math.min(a, b).toDouble());
      case 'CONTAR':
        return _values(args).where((v) => v != null && v.toString().trim().isNotEmpty).length;
      case 'CONTARSI':
        if (args.length < 2) return 0;
        final values = _values([args[0]]);
        return values.where((v) => _matchesCriteria(v, args[1])).length;
      case 'SUMARSI':
        if (args.length < 2) return 0;
        final criteriaValues = _values([args[0]]);
        final sumValues = args.length >= 3 ? _values([args[2]]) : criteriaValues;
        var total = 0.0;
        for (var i = 0; i < criteriaValues.length; i++) {
          if (_matchesCriteria(criteriaValues[i], args[1])) total += _toDouble(i < sumValues.length ? sumValues[i] : null);
        }
        return total;
      case 'PROMEDIOSI':
        if (args.length < 2) return 0;
        final criteriaValues = _values([args[0]]);
        final avgValues = args.length >= 3 ? _values([args[2]]) : criteriaValues;
        final selected = <double>[];
        for (var i = 0; i < criteriaValues.length; i++) {
          if (_matchesCriteria(criteriaValues[i], args[1])) selected.add(_toDouble(i < avgValues.length ? avgValues[i] : null));
        }
        return selected.isEmpty ? 0 : selected.reduce((a, b) => a + b) / selected.length;
      case 'MEDIANA':
        return _median(_values(args).map(_toDouble).toList());
      case 'MODA':
        return _mode(_values(args).map(_toDouble).toList());
      case 'MEDIANASI':
        return _conditionalStatistic(args, median: true);
      case 'MODASI':
        return _conditionalStatistic(args, median: false);
      case 'IF':
      case 'SI':
        if (args.length < 3) return '';
        return _evalCondition(args[0]) ? _evalExpression(args[1]) : _evalExpression(args[2]);
      case 'IFERROR':
      case 'SIERROR':
        if (args.isEmpty) return '';
        try {
          final value = _evalExpression(args[0]);
          if (value == null || value.toString().trim().isEmpty) {
            return args.length > 1 ? _evalExpression(args[1]) : '';
          }
          if (value is num && (value.isNaN || value.isInfinite)) {
            return args.length > 1 ? _evalExpression(args[1]) : '';
          }
          return value;
        } catch (_) {
          return args.length > 1 ? _evalExpression(args[1]) : '';
        }
      case 'ES_VACIO':
      case 'ESVACIO':
      case 'VACIO':
        return args.isEmpty ? true : _asText(_evalExpression(args.first)).trim().isEmpty;
      case 'NO_ES_VACIO':
      case 'NOESVACIO':
      case 'NOVACIO':
        return args.isEmpty ? false : _asText(_evalExpression(args.first)).trim().isNotEmpty;
      case 'AND':
      case 'Y':
        return args.every(_evalCondition);
      case 'OR':
      case 'O':
        return args.any(_evalCondition);
      case 'NOT':
      case 'NO':
        return args.isEmpty ? false : !_evalCondition(args.first);
      case 'CONCAT':
      case 'CONCATENAR':
        return args.map((a) => _asText(_evalExpression(a))).join();
      case 'CONCATENAR_ESPACIO':
        return args.map((a) => _asText(_evalExpression(a))).where((v) => v.trim().isNotEmpty).join(' ');
      case 'CONCATENAR_SEP':
        if (args.isEmpty) return '';
        final sep = _asText(_evalExpression(args.first));
        return args.skip(1).map((a) => _asText(_evalExpression(a))).where((v) => v.trim().isNotEmpty).join(sep);
      case 'LEFT':
      case 'IZQUIERDA':
        if (args.isEmpty) return '';
        final text = _asText(_evalExpression(args[0]));
        final count = args.length > 1 ? _toDouble(_evalExpression(args[1])).round() : 1;
        final safe = math.max(0, math.min(count, text.length)).toInt();
        return text.substring(0, safe);
      case 'RIGHT':
      case 'DERECHA':
        if (args.isEmpty) return '';
        final text = _asText(_evalExpression(args[0]));
        final count = args.length > 1 ? _toDouble(_evalExpression(args[1])).round() : 1;
        final safe = math.max(0, math.min(count, text.length)).toInt();
        return text.substring(text.length - safe);
      case 'MID':
      case 'EXTRAER':
      case 'SUBSTRING':
        if (args.length < 2) return '';
        final text = _asText(_evalExpression(args[0]));
        final startOneBased = _toDouble(_evalExpression(args[1])).round();
        final start = math.max(0, startOneBased - 1).toInt();
        final len = args.length > 2 ? _toDouble(_evalExpression(args[2])).round() : text.length;
        if (start >= text.length || len <= 0) return '';
        final end = math.min(text.length, start + len).toInt();
        return text.substring(start, end);
      case 'LEN':
      case 'LARGO':
        if (args.isEmpty) return 0;
        return _asText(_evalExpression(args[0])).length;
      case 'UPPER':
      case 'MAYUSC':
      case 'MAYUSCULAS':
        return args.isEmpty ? '' : _asText(_evalExpression(args[0])).toUpperCase();
      case 'LOWER':
      case 'MINUSC':
      case 'MINUSCULAS':
        return args.isEmpty ? '' : _asText(_evalExpression(args[0])).toLowerCase();
      case 'TRIM':
      case 'ESPACIOS':
      case 'LIMPIAR':
        return args.isEmpty ? '' : _asText(_evalExpression(args[0])).trim().replaceAll(RegExp(r'\s+'), ' ');
      case 'REPLACE':
      case 'REEMPLAZAR':
        if (args.length < 3) return '';
        return _asText(_evalExpression(args[0])).replaceAll(_asText(_evalExpression(args[1])), _asText(_evalExpression(args[2])));
      case 'CONTAINS':
      case 'CONTIENE':
        if (args.length < 2) return false;
        return _asText(_evalExpression(args[0])).toUpperCase().contains(_asText(_evalExpression(args[1])).toUpperCase());
      case 'STARTSWITH':
      case 'EMPIEZA_CON':
        if (args.length < 2) return false;
        return _asText(_evalExpression(args[0])).toUpperCase().startsWith(_asText(_evalExpression(args[1])).toUpperCase());
      case 'ENDSWITH':
      case 'TERMINA_CON':
        if (args.length < 2) return false;
        return _asText(_evalExpression(args[0])).toUpperCase().endsWith(_asText(_evalExpression(args[1])).toUpperCase());
      case 'ABS':
      case 'ABSOLUTO':
        return args.isEmpty ? 0 : _toDouble(_evalExpression(args[0])).abs();
      case 'INT':
      case 'ENTERO':
        return args.isEmpty ? 0 : _toDouble(_evalExpression(args[0])).floor();
      case 'POWER':
      case 'POTENCIA':
        if (args.length < 2) return 0;
        return math.pow(_toDouble(_evalExpression(args[0])), _toDouble(_evalExpression(args[1]))).toDouble();
      case 'MOD':
      case 'RESIDUO':
        if (args.length < 2) return 0;
        final divisor = _toDouble(_evalExpression(args[1]));
        return divisor == 0 ? double.nan : _toDouble(_evalExpression(args[0])) % divisor;
      case 'LOOKUP':
      case 'BUSCAR':
        return _lookup(args);
      case 'LIST':
      case 'LISTA':
        return _list(args);
      case 'SEMANA':
        return _datePart(args, 'SEMANA');
      case 'ANIO':
        return _datePart(args, 'ANIO');
      case 'MES':
        return _datePart(args, 'MES');
      case 'DIA':
        return _datePart(args, 'DIA');
      case 'NUM':
      case 'NUMERO':
      case 'VALOR':
        if (args.isEmpty) return 0;
        final rawArg = args[0].trim();
        if (_isFieldRef(rawArg)) return _toDouble(_resolveField(rawArg));
        return _toDouble(_evalExpression(rawArg));
      case 'ROUND':
      case 'REDONDEAR':
        if (args.isEmpty) return 0;
        final value = _toDouble(_evalExpression(args[0]));
        final decimals = args.length > 1 ? _toDouble(_evalExpression(args[1])).round() : 0;
        return double.parse(value.toStringAsFixed(decimals));
      default:
        return 0;
    }
  }

  String _normalizeFunction(String name) {
    var s = _normalize(name).replaceAll('.', '').replaceAll('_', '');
    const aliases = {
      'SUM': 'SUMA',
      'SUMAR': 'SUMA',
      'RESTATIEMPO': 'RESTA_TIEMPOS',
      'RESTATIEMPOS': 'RESTA_TIEMPOS',
      'RESTA_TIEMPO': 'RESTA_TIEMPOS',
      'RESTA_TIEMPOS': 'RESTA_TIEMPOS',
      'FECHASTRANSCURRIDAS': 'FECHAS_TRANSCURRIDAS',
      'FECHAS_TRANSCURRIDAS': 'FECHAS_TRANSCURRIDAS',
      'DIAS_TRANSCURRIDOS': 'FECHAS_TRANSCURRIDAS',
      'DIASTRANSCURRIDOS': 'FECHAS_TRANSCURRIDAS',
      'SUMARDIAS': 'SUMAR_DIAS',
      'SUMAR_DIAS': 'SUMAR_DIAS',
      'HORAACTUAL': 'HORA_ACTUAL',
      'HORA_ACTUAL': 'HORA_ACTUAL',
      'AHORAHORA': 'AHORA_HORA',
      'AHORA_HORA': 'AHORA_HORA',
      'FECHAACTUAL': 'FECHA_ACTUAL',
      'FECHA_ACTUAL': 'FECHA_ACTUAL',
      'FECHAHORAACTUAL': 'FECHA_HORA_ACTUAL',
      'FECHAHORA_ACTUAL': 'FECHA_HORA_ACTUAL',
      'FECHA_HORA_ACTUAL': 'FECHA_HORA_ACTUAL',
      'AVG': 'PROMEDIO',
      'AVERAGE': 'PROMEDIO',
      'COUNT': 'CONTAR',
      'COUNTIF': 'CONTARSI',
      'CONTARSI': 'CONTARSI',
      'SUMIF': 'SUMARSI',
      'SUMARSI': 'SUMARSI',
      'AVERAGEIF': 'PROMEDIOSI',
      'PROMEDIOSI': 'PROMEDIOSI',
      'MEDIAN': 'MEDIANA',
      'MODE': 'MODA',
      'MEDIANIF': 'MEDIANASI',
      'MEDIANASI': 'MEDIANASI',
      'MODEIF': 'MODASI',
      'MODASI': 'MODASI',
      'MULT': 'MULTIPLICACION',
      'PRODUCTO': 'MULTIPLICACION',
      'MULTIPLICAR': 'MULTIPLICACION',
      'DIV': 'DIVISION',
      'DIVIDIR': 'DIVISION',
      'SQRT': 'RAIZ',
      'RAIZCUADRADA': 'RAIZ',
      'MAX': 'MAXIMO',
      'MIN': 'MINIMO',
      'SI': 'SI',
      'IF': 'IF',
      'ESVACIO': 'ES_VACIO',
      'ES_VACIO': 'ES_VACIO',
      'VACIO': 'ES_VACIO',
      'NOESVACIO': 'NO_ES_VACIO',
      'NO_ES_VACIO': 'NO_ES_VACIO',
      'NOVACIO': 'NO_ES_VACIO',
      'IFERROR': 'IFERROR',
      'SIERROR': 'SIERROR',
      'AND': 'AND',
      'Y': 'Y',
      'OR': 'OR',
      'O': 'O',
      'NOT': 'NOT',
      'NO': 'NO',
      'CONCAT': 'CONCAT',
      'CONCATENAR': 'CONCATENAR',
      'CONTATENAR': 'CONCATENAR',
      'CONCATENARESPACIO': 'CONCATENAR_ESPACIO',
      'CONCATENARSEP': 'CONCATENAR_SEP',
      'LEFT': 'LEFT',
      'IZQUIERDA': 'IZQUIERDA',
      'RIGHT': 'RIGHT',
      'DERECHA': 'DERECHA',
      'MID': 'MID',
      'EXTRAER': 'EXTRAER',
      'SUBSTRING': 'SUBSTRING',
      'LEN': 'LEN',
      'LARGO': 'LARGO',
      'UPPER': 'UPPER',
      'MAYUSC': 'MAYUSC',
      'MAYUSCULAS': 'MAYUSCULAS',
      'LOWER': 'LOWER',
      'MINUSC': 'MINUSC',
      'MINUSCULAS': 'MINUSCULAS',
      'TRIM': 'TRIM',
      'ESPACIOS': 'ESPACIOS',
      'LIMPIAR': 'LIMPIAR',
      'REPLACE': 'REPLACE',
      'REEMPLAZAR': 'REEMPLAZAR',
      'CONTAINS': 'CONTAINS',
      'CONTIENE': 'CONTIENE',
      'STARTSWITH': 'STARTSWITH',
      'EMPIEZACON': 'EMPIEZA_CON',
      'ENDSWITH': 'ENDSWITH',
      'TERMINACON': 'TERMINA_CON',
      'ABS': 'ABS',
      'ABSOLUTO': 'ABSOLUTO',
      'INT': 'INT',
      'ENTERO': 'ENTERO',
      'POWER': 'POWER',
      'POTENCIA': 'POTENCIA',
      'MOD': 'MOD',
      'RESIDUO': 'RESIDUO',
      'LOOKUP': 'LOOKUP',
      'LOOKUPR': 'LOOKUP',
      'LOOKUPP': 'LOOKUP',
      'BUSCAR': 'BUSCAR',
      'LIST': 'LISTA',
      'LISTA': 'LISTA',
      'WEEK': 'SEMANA',
      'YEAR': 'ANIO',
      'ANO': 'ANIO',
      'AÑO': 'ANIO',
      'MONTH': 'MES',
      'DAY': 'DIA',
      'NUM': 'NUM',
      'NUMERO': 'NUMERO',
      'VALOR': 'VALOR',
      'ROUND': 'ROUND',
      'REDONDEAR': 'REDONDEAR',
    };
    return aliases[s] ?? s;
  }

  List<dynamic> _values(List<String> args) {
    final out = <dynamic>[];
    for (final arg in args) {
      if (_isRange(arg)) {
        out.addAll(_valuesFromRange(arg));
      } else {
        out.add(_evalExpression(arg));
      }
    }
    return out;
  }

  bool _isRange(String arg) {
    final s = _stripFieldDelimiters(arg.trim());
    return s.contains(':') && !s.contains('://');
  }

  List<dynamic> _valuesFromRange(String arg) {
    final clean = _stripFieldDelimiters(arg.trim());
    final parts = clean.split(':');
    if (parts.length != 2) return const [];
    final start = _fieldByIdentifier(parts[0]);
    final end = _fieldByIdentifier(parts[1]);
    if (start == null || end == null) return const [];
    final startOrder = _toDouble(start['orden']).round();
    final endOrder = _toDouble(end['orden']).round();
    final minOrder = math.min(startOrder, endOrder);
    final maxOrder = math.max(startOrder, endOrder);
    final selected = fields.where((f) {
      final order = _toDouble(f['orden']).round();
      return order >= minOrder && order <= maxOrder;
    }).toList()
      ..sort((a, b) => _toDouble(a['orden']).compareTo(_toDouble(b['orden'])));
    return selected.map((f) => getValue(f['campo']?.toString() ?? '')).toList();
  }

  Map<String, dynamic>? _fieldByIdentifier(String identifier) {
    final wanted = _normalize(_stripFieldDelimiters(identifier));
    for (final f in fields) {
      final id = _normalize(f['id']?.toString() ?? '');
      final campo = _normalize(f['campo']?.toString() ?? '');
      final etiqueta = _normalize(f['etiqueta']?.toString() ?? '');
      if (wanted == id || wanted == campo || wanted == etiqueta) return f;
    }
    return null;
  }

  dynamic _resolveField(String token) {
    final identifier = _stripFieldDelimiters(token);
    final field = _fieldByIdentifier(identifier);
    if (field != null) return getValue(field['campo']?.toString() ?? '');
    return getValue(identifier);
  }

  String _replaceFieldReferencesForMath(String expr) {
    String numberForRef(String token) {
      final value = _resolveField(token);
      return _toDouble(value).toString();
    }

    // La referencia completa se protege antes de evaluar la matemática.
    // Soporta nombres con paréntesis: [CANT(JABAS)]
    // Soporta UUID con guiones: [d514ff1c-be45-48cb-84b2-e2155cd754dc]
    var out = expr.replaceAllMapped(RegExp(r'\[([^\]]+)\]'), (m) => numberForRef(m.group(0)!));
    out = out.replaceAllMapped(RegExp(r'\{\{([^}]+)\}\}'), (m) => numberForRef(m.group(0)!));
    return out;
  }

  bool _evalCondition(String condition) {
    final ops = ['>=', '<=', '==', '!=', '=', '>', '<'];
    for (final op in ops) {
      final idx = _indexOfOperator(condition, op);
      if (idx < 0) continue;
      final left = _evalExpression(condition.substring(0, idx));
      final right = _evalExpression(condition.substring(idx + op.length));
      final leftNum = double.tryParse(left.toString().replaceAll(',', '.'));
      final rightNum = double.tryParse(right.toString().replaceAll(',', '.'));
      if (leftNum != null && rightNum != null) {
        switch (op) {
          case '>': return leftNum > rightNum;
          case '<': return leftNum < rightNum;
          case '>=': return leftNum >= rightNum;
          case '<=': return leftNum <= rightNum;
          case '==':
          case '=': return leftNum == rightNum;
          case '!=': return leftNum != rightNum;
        }
      } else {
        final a = left.toString().trim();
        final b = right.toString().trim();
        switch (op) {
          case '==':
          case '=': return _normalize(a) == _normalize(b);
          case '!=': return _normalize(a) != _normalize(b);
          case '>': return a.compareTo(b) > 0;
          case '<': return a.compareTo(b) < 0;
          case '>=': return a.compareTo(b) >= 0;
          case '<=': return a.compareTo(b) <= 0;
        }
      }
    }
    final value = _evalExpression(condition);
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().trim().isNotEmpty;
  }

  int _indexOfOperator(String text, String op) {
    var level = 0;
    var inString = false;
    String? quote;
    var squareLevel = 0;
    var braceLevel = 0;

    for (var i = 0; i <= text.length - op.length; i++) {
      final c = text[i];
      if ((c == "'" || c == '"')) {
        if (!inString) {
          inString = true;
          quote = c;
        } else if (quote == c) {
          inString = false;
          quote = null;
        }
      }
      if (inString) continue;

      if (c == '[') {
        squareLevel++;
        continue;
      }
      if (c == ']' && squareLevel > 0) {
        squareLevel--;
        continue;
      }
      if (c == '{' && i + 1 < text.length && text[i + 1] == '{') {
        braceLevel++;
        i++;
        continue;
      }
      if (c == '}' && i + 1 < text.length && text[i + 1] == '}' && braceLevel > 0) {
        braceLevel--;
        i++;
        continue;
      }
      if (squareLevel > 0 || braceLevel > 0) continue;

      if (c == '(') level++;
      if (c == ')') level--;
      if (level == 0 && text.substring(i, i + op.length) == op) {
        if (op == '=') {
          final prev = i > 0 ? text[i - 1] : '';
          final next = i + 1 < text.length ? text[i + 1] : '';
          if (prev == '>' || prev == '<' || prev == '!' || prev == '=' || next == '=') continue;
        }
        return i;
      }
    }
    return -1;
  }

  bool _matchesCriteria(dynamic value, String criteriaRaw) {
    var criteria = criteriaRaw.trim();
    if (_isQuoted(criteria)) criteria = _unquote(criteria);
    final match = RegExp(r'^(>=|<=|==|!=|=|>|<)\s*(.*)$').firstMatch(criteria);
    if (match == null) {
      return value.toString().trim() == criteria.trim();
    }
    final op = match.group(1)!;
    final rightText = match.group(2)!.trim();
    final leftNum = double.tryParse(value.toString().replaceAll(',', '.'));
    final rightNum = double.tryParse(rightText.replaceAll(',', '.'));
    if (leftNum != null && rightNum != null) {
      switch (op) {
        case '>': return leftNum > rightNum;
        case '<': return leftNum < rightNum;
        case '>=': return leftNum >= rightNum;
        case '<=': return leftNum <= rightNum;
        case '==':
        case '=': return leftNum == rightNum;
        case '!=': return leftNum != rightNum;
      }
    }
    switch (op) {
      case '==':
      case '=': return _normalize(value.toString()) == _normalize(rightText);
      case '!=': return _normalize(value.toString()) != _normalize(rightText);
    }
    return false;
  }

  dynamic _lookup(List<String> args) {
    if (args.length < 4) return '';
    final sourceTable = _cleanToken(args[0]);
    final searchColumn = _cleanToken(args[1]);
    final searchValue = _evalExpression(args[2]).toString().trim();
    final returnColumn = _cleanToken(args[3]);
    final rows = matrixRowsByTable[sourceTable] ?? const <Map<String, dynamic>>[];
    for (final row in rows) {
      final candidate = _valueByColumnName(row, searchColumn)?.toString().trim() ?? '';
      if (candidate == searchValue) {
        return _valueByColumnName(row, returnColumn)?.toString().trim() ?? '';
      }
    }
    return '';
  }

  String _list(List<String> args) {
    if (args.length < 2) return '';
    final sourceTable = _cleanToken(args[0]);
    final returnColumn = _cleanToken(args[1]);
    final filterColumn = args.length >= 4 ? _cleanToken(args[2]) : '';
    final filterValue = args.length >= 4
        ? _evalExpression(args[3]).toString().trim()
        : '';
    final values = <String>[];
    for (final row in matrixRowsByTable[sourceTable] ?? const []) {
      if (filterColumn.isNotEmpty) {
        final candidate =
            _valueByColumnName(row, filterColumn)?.toString().trim() ?? '';
        if (candidate != filterValue) continue;
      }
      final value = _valueByColumnName(row, returnColumn)?.toString().trim() ?? '';
      if (value.isNotEmpty && !values.contains(value)) values.add(value);
    }
    return values.join(', ');
  }

  dynamic _valueByColumnName(Map<String, dynamic> row, String column) {
    final wanted = _normalize(column);
    for (final entry in row.entries) {
      if (_normalize(entry.key) == wanted) return entry.value;
    }
    return null;
  }

  dynamic _datePart(List<String> args, String part) {
    if (args.isEmpty) return '';
    final raw = _evalExpression(args.first).toString().trim();
    final date = DateTime.tryParse(raw);
    if (date == null) return '';
    switch (part) {
      case 'SEMANA': return _isoWeek(date);
      case 'ANIO': return date.year;
      case 'MES': return date.month;
      case 'DIA': return date.day;
    }
    return '';
  }

  int _isoWeek(DateTime date) {
    final thursday = date.add(Duration(days: 3 - ((date.weekday + 6) % 7)));
    final firstThursday = DateTime(thursday.year, 1, 4);
    return 1 + thursday.difference(firstThursday.add(Duration(days: 3 - ((firstThursday.weekday + 6) % 7)))).inDays ~/ 7;
  }

  double _conditionalStatistic(List<String> args, {required bool median}) {
    if (args.length < 2) return 0;
    final criteriaValues = _values([args[0]]);
    final statValues = args.length >= 3 ? _values([args[2]]) : criteriaValues;
    final selected = <double>[];
    for (var i = 0; i < criteriaValues.length; i++) {
      if (_matchesCriteria(criteriaValues[i], args[1])) selected.add(_toDouble(i < statValues.length ? statValues[i] : null));
    }
    return median ? _median(selected) : _mode(selected);
  }

  double _median(List<double> values) {
    final nums = values.where((v) => !v.isNaN && !v.isInfinite).toList()..sort();
    if (nums.isEmpty) return 0;
    final mid = nums.length ~/ 2;
    return nums.length.isOdd ? nums[mid] : (nums[mid - 1] + nums[mid]) / 2;
  }

  double _mode(List<double> values) {
    final counts = <double, int>{};
    for (final v in values.where((v) => !v.isNaN && !v.isInfinite)) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    if (counts.isEmpty) return 0;
    var best = counts.entries.first;
    for (final e in counts.entries) {
      if (e.value > best.value) best = e;
    }
    return best.key;
  }

  String _asText(dynamic value) {
    if (value == null) return '';
    if (value is num) return _formatNumber(value.toDouble());
    return value.toString();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    var text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return 0;
    // Soporta valores escritos como 1,25 o 1,234.50 sin romper cálculos.
    text = text.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(r'^-?\d{1,3}(,\d{3})+(\.\d+)?$').hasMatch(text)) {
      text = text.replaceAll(',', '');
    } else {
      text = text.replaceAll(',', '.');
    }
    return double.tryParse(text) ?? 0;
  }

  String _unquote(String value) {
    var out = value.trim();
    var changed = true;
    while (changed && out.length >= 2) {
      changed = false;
      if ((out.startsWith("'") && out.endsWith("'")) || (out.startsWith('"') && out.endsWith('"'))) {
        out = out.substring(1, out.length - 1);
        changed = true;
      }
    }
    return out.replaceAll("''", "'").replaceAll('""', '"');
  }

  bool _isQuoted(String value) =>
      value.length >= 2 && ((value.startsWith("'") && value.endsWith("'")) || (value.startsWith('"') && value.endsWith('"')));

  bool _isFieldRef(String value) {
    final v = value.trim();
    // Debe ser UNA referencia completa, no una expresión como [A] - [B].
    // Antes, cualquier texto que empezaba con [ y terminaba con ] se trataba
    // como un solo campo; eso podía romper fórmulas con varias referencias.
    return RegExp(r'^\[[^\[\]]+\]$').hasMatch(v) ||
        RegExp(r'^\{\{[^{}]+\}\}$').hasMatch(v);
  }

  bool _isDateLiteral(String value) => RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(value);

  int? _timeMinutesFromArg(String arg) {
    final evaluated = _evalExpression(arg);
    return _timeMinutes(evaluated) ?? _timeMinutes(_stripFieldDelimiters(arg));
  }

  int? _timeMinutes(dynamic value) {
    if (value == null) return null;
    var text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    if ((text.startsWith('[') && text.endsWith(']')) || (text.startsWith('{{') && text.endsWith('}}'))) {
      text = _stripFieldDelimiters(text);
    }
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(text.trim());
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!);
    final m = int.tryParse(match.group(2)!);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return null;
    return h * 60 + m;
  }

  String _formatDuration(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) return hours == 1 ? '1 hora' : '$hours horas';
    if (hours == 0) return minutes == 1 ? '1 minuto' : '$minutes minutos';
    final hText = hours == 1 ? '1 hora' : '$hours horas';
    final mText = minutes == 1 ? '1 minuto' : '$minutes minutos';
    return '$hText $mText';
  }

  DateTime? _tryParseFormulaDate(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text.toUpperCase() == 'NULL') return null;
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(text);
    if (iso != null) {
      return DateTime.tryParse('${iso.group(1)!}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}');
    }
    final slash = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})$').firstMatch(text);
    if (slash != null) {
      final d = int.tryParse(slash.group(1)!);
      final m = int.tryParse(slash.group(2)!);
      final y = int.tryParse(slash.group(3)!);
      if (d == null || m == null || y == null) return null;
      final dt = DateTime(y, m, d);
      return dt.year == y && dt.month == m && dt.day == d ? dt : null;
    }
    return DateTime.tryParse(text);
  }

  DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  String _formatFormulaDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatFormulaTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatFormulaDateTime(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '${_formatFormulaDate(date)} $h:$m:$s';
  }

  bool _isPlainIdentifier(String value) => RegExp(r'^[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_. -]+$').hasMatch(value.trim());

  String _stripFieldDelimiters(String value) {
    var out = value.trim();
    if (out.startsWith('[') && out.endsWith(']')) out = out.substring(1, out.length - 1);
    if (out.startsWith('{{') && out.endsWith('}}')) out = out.substring(2, out.length - 2);
    return out.trim();
  }

  String _cleanToken(String value) {
    var out = value.trim();
    if (_isQuoted(out)) out = _unquote(out);
    return _stripFieldDelimiters(out);
  }

  String _normalize(String value) {
    var s = value.trim().toUpperCase();
    const acentos = {'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O', 'Ú': 'U', 'Ü': 'U', 'Ñ': 'N'};
    acentos.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'[^A-Z0-9]+'), '_');
    s = s.replaceAll(RegExp(r'_+'), '_');
    return s.replaceAll(RegExp(r'^_|_$'), '');
  }

  String _formatNumber(double value) {
    if (value.isNaN || value.isInfinite) return '';
    return value.truncateToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
}

class _FunctionCall {
  final String name;
  final List<String> args;
  final int start;
  final int end;

  _FunctionCall({required this.name, required this.args, required this.start, required this.end});
}

class _ExpressionParser {
  final String input;
  int _pos = 0;

  _ExpressionParser(this.input);

  double parse() {
    final value = _parseExpression();
    _skipSpaces();
    // No aceptar resultados parciales. Antes, '0.20 * NUM(...)' podía terminar
    // devolviendo solo 0.20 si quedaban tokens sin consumir. Eso ocultaba errores.
    if (_pos < input.length) return double.nan;
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parsePower();
    while (true) {
      _skipSpaces();
      if (_match('*')) {
        if (_match('*')) {
          _pos -= 2;
          return value;
        }
        value *= _parsePower();
      } else if (_match('/')) {
        final divisor = _parsePower();
        value = divisor == 0 ? double.nan : value / divisor;
      } else {
        return value;
      }
    }
  }

  double _parsePower() {
    var value = _parseFactor();
    _skipSpaces();
    if (_match('*')) {
      if (_match('*')) {
        value = math.pow(value, _parsePower()).toDouble();
      } else {
        _pos--;
      }
    }
    return value;
  }

  double _parseFactor() {
    _skipSpaces();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('√')) {
      final value = _parseFactor();
      return value < 0 ? double.nan : math.sqrt(value);
    }
    if (_match('(')) {
      final value = _parseExpression();
      _match(')');
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _pos;
    while (_pos < input.length && RegExp(r'[0-9.]').hasMatch(input[_pos])) {
      _pos++;
    }
    if (start == _pos) return 0;
    return double.tryParse(input.substring(start, _pos)) ?? 0;
  }

  bool _match(String char) {
    _skipSpaces();
    if (_pos < input.length && input[_pos] == char) {
      _pos++;
      return true;
    }
    return false;
  }

  void _skipSpaces() {
    while (_pos < input.length && input[_pos].trim().isEmpty) {
      _pos++;
    }
  }
}
