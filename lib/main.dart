import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async  {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();
  runApp(const MyApp());
}

class CalorieEntry {
  String food;
  String quantity;
  int calories;
  int protein; // New field for protein
  DateTime time;

  CalorieEntry(this.food, this.quantity, this.calories, this.protein, this.time);

  Map<String, dynamic> toMap() => {
        'food': food,
        'quantity': quantity,
        'calories': calories,
        'protein': protein, // Include protein in the map
        'time': time.toIso8601String(),
      };

  factory CalorieEntry.fromMap(Map<String, dynamic> map) => CalorieEntry(
        map['food'],
        map['quantity'],
        map['calories'],
        map['protein'], // Parse protein from the map
        DateTime.parse(map['time']),
      );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Calorie Tracker',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.teal),
          bodyMedium: TextStyle(fontSize: 16, color: Colors.black87),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ),
      home: const MyHomePage(title: 'Calorie Tracker'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Map<String, List<CalorieEntry>> _entries = {};
  DateTime _selectedDate = DateTime.now();
  final List<DateTime> _dates = List.generate(30, (i) => DateTime.now().subtract(Duration(days: i))).toList();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? data = prefs.getString('calorieEntries');
    if (data != null) {
      Map<String, dynamic> decoded = json.decode(data);
      setState(() {
        _entries = decoded.map((k, v) => MapEntry(k, (v as List).map((e) => CalorieEntry.fromMap(e)).toList()));
      });
    }
  }

  Future<void> _saveEntries() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> data = _entries.map((k, v) => MapEntry(k, v.map((e) => e.toMap()).toList()));
    await prefs.setString('calorieEntries', json.encode(data));
  }

  Future<Map<String, int>> _getCaloriesAndProtein(String food, String quantity) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    final model = GenerativeModel(model: 'gemini-3-flash-preview', apiKey: apiKey!);
    final prompt = 'Estimate the calories and protein content in $quantity of $food. Return the result in the format: "calories: <calories>, protein: <protein>".';
    final response = await model.generateContent([Content.text(prompt)]);
    String text = response.text?.trim() ?? '';

    // Extract calories and protein from the response
    final regExp = RegExp(r'calories:\s*(\d+),\s*protein:\s*(\d+)');
    final match = regExp.firstMatch(text);

    if (match != null) {
      final calories = int.parse(match.group(1)!);
      final protein = int.parse(match.group(2)!);
      return {'calories': calories, 'protein': protein};
    }

    return {'calories': 0, 'protein': 0};
  }

  void _addEntry() {
    final TextEditingController foodController = TextEditingController();
    final TextEditingController quantityController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Food'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: foodController,
              decoration: const InputDecoration(labelText: 'Food Name'),
            ),
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(labelText: 'Quantity (e.g., 1 apple, 100g rice)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final food = foodController.text.trim();
              final quantity = quantityController.text.trim();
              if (food.isNotEmpty && quantity.isNotEmpty) {
                try {
                  final result = await _getCaloriesAndProtein(food, quantity);
                  final entry = CalorieEntry(food, quantity, result['calories']!, result['protein']!, DateTime.now());
                  final dateKey = _selectedDate.toIso8601String().split('T')[0];
                  setState(() {
                    _entries[dateKey] = (_entries[dateKey] ?? [])..add(entry);
                  });
                  _saveEntries();
                  // ignore: use_build_context_synchronously
                  Navigator.of(context).pop();
                } catch (e) {
                  // Handle error, perhaps show snackbar
                  // ignore: use_build_context_synchronously
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error estimating values: $e')),
                  );
                }
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  int _getTotalForDate(DateTime date) {
    final dateKey = date.toIso8601String().split('T')[0];
    return _entries[dateKey]?.fold<int>(0, (sum, e) => sum + e.calories) ?? 0;
  }

  int _getTotalProteinForDate(DateTime date) {
    final dateKey = date.toIso8601String().split('T')[0];
    return _entries[dateKey]?.fold<int>(0, (sum, e) => sum + e.protein) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = _selectedDate.toIso8601String().split('T')[0];
    final entries = _entries[dateKey] ?? [];
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.teal, Colors.greenAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  'Date: ${_selectedDate.toLocal().toString().split(' ')[0]}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  'Total Calories: ${_getTotalForDate(_selectedDate)}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Total Protein: ${_getTotalProteinForDate(_selectedDate)}g',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 60,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Center(
                child: ToggleButtons(
                  isSelected: _dates.map((date) => date == _selectedDate).toList(),
                  onPressed: (index) {
                    setState(() {
                      _selectedDate = _dates[index];
                    });
                  },
                  borderRadius: BorderRadius.circular(20),
                  selectedColor: Colors.white,
                  fillColor: Theme.of(context).colorScheme.primary,
                  color: Colors.black,
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  constraints: const BoxConstraints(minWidth: 60, minHeight: 40),
                  children: _dates.map((date) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text('${date.month}/${date.day}'),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 4,
                  child: ListTile(
                    title: Text(
                      entry.food,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      '${entry.quantity} - ${entry.calories} cal, ${entry.protein}g protein at ${entry.time.hour}:${entry.time.minute.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () {
                            final TextEditingController caloriesController = TextEditingController(text: entry.calories.toString());
                            final TextEditingController proteinController = TextEditingController(text: entry.protein.toString());
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Edit Entry'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: caloriesController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Calories'),
                                    ),
                                    TextField(
                                      controller: proteinController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(labelText: 'Protein (g)'),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      final newCalories = int.tryParse(caloriesController.text.trim());
                                      final newProtein = int.tryParse(proteinController.text.trim());
                                      if (newCalories != null && newProtein != null) {
                                        setState(() {
                                          entry.calories = newCalories;
                                          entry.protein = newProtein;
                                          _saveEntries();
                                        });
                                        // ignore: use_build_context_synchronously
                                        Navigator.of(context).pop();
                                      } else {
                                        // ignore: use_build_context_synchronously
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please enter valid numbers.')),
                                        );
                                      }
                                    },
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() {
                              _entries[dateKey]?.removeAt(index);
                              _saveEntries();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEntry,
        tooltip: 'Add Food',
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
