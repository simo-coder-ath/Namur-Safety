import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart'; // Pour formater les dates
import 'package:latlong2/latlong.dart'; // Utilisez latlong2
import 'package:cloud_firestore/cloud_firestore.dart'; // Ajouter Firestore
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'firstpage.dart'; // Importation de firstapp.dart
import 'welcome.dart'; // Importation de welcome.dart pour l'animation






void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Namur Safety',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: AnimatedTextPage(), // Démarrer l'application avec l'animation de welcome.dart
    );
  }
}

class MainFormPage extends StatefulWidget {
  const MainFormPage({super.key});

  @override
  _MainFormPageState createState() => _MainFormPageState();
}

class _MainFormPageState extends State<MainFormPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String? _nom;
  String? _prenom;
  DateTime? _dateAgression;
  String? _gravite;
  String? _description; // Ajout de la description
  LatLng? _selectedPosition; // Pour la position sélectionnée sur la carte

  final List<String> _graviteOptions = ['Faible', 'Moyenne', 'Élevée'];
  final LatLng _namurCoordinates = LatLng(50.4675, 4.8711);
  double _zoom = 13.0;

  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 0.5).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _dateAgression) {
      setState(() {
        _dateAgression = picked;
      });
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      try {
        // Enregistrez les données dans Firestore
        await FirebaseFirestore.instance.collection('agressions').add({
          'nom': _nom,
          'prenom': _prenom,
          'date_agression': _dateAgression != null ? _dateAgression!.toIso8601String() : null,
          'gravite': _gravite,
          'description': _description, // Enregistrement de la description
          'position': [
            _selectedPosition?.latitude,
            _selectedPosition?.longitude,
          ],
          'timestamp': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Déclaration soumise avec succès')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Déclaration d\'agression'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Champ Nom
              TextFormField(
                decoration: const InputDecoration(labelText: 'Nom'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer le nom';
                  }
                  return null;
                },
                onSaved: (value) {
                  _nom = value;
                },
              ),
              const SizedBox(height: 10),

              // Champ Prénom
              TextFormField(
                decoration: const InputDecoration(labelText: 'Prénom'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer le prénom';
                  }
                  return null;
                },
                onSaved: (value) {
                  _prenom = value;
                },
              ),
              const SizedBox(height: 10),

              // Sélecteur de Date
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _dateAgression == null
                          ? 'Aucune date choisie'
                          : 'Date: ${DateFormat('dd/MM/yyyy').format(_dateAgression!)}',
                    ),
                  ),
                  TextButton(
                    onPressed: () => _selectDate(context),
                    child: const Text('Choisir une date'),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Sélecteur de gravité
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Gravité'),
                items: _graviteOptions.map((String gravite) {
                  return DropdownMenuItem<String>(
                    value: gravite,
                    child: Text(gravite),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _gravite = value;
                  });
                },
                validator: (value) => value == null ? 'Veuillez choisir un niveau de gravité' : null,
                onSaved: (value) {
                  _gravite = value;
                },
              ),
              const SizedBox(height: 10),

              // Champ Description
              TextFormField(
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3, // Permet d'entrer plusieurs lignes
                onSaved: (value) {
                  _description = value;
                },
              ),
              const SizedBox(height: 20),

              // Carte avec la localisation
              SizedBox(
                height: 300,
                child: FlutterMap(
                  options: MapOptions(
                    center: _namurCoordinates,
                    zoom: _zoom,
                    onTap: (tapPosition, point) {
                      setState(() {
                        _selectedPosition = point; // Mettez à jour la position sélectionnée
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                      subdomains: ['a', 'b', 'c'],
                    ),
                    // Ajout du marqueur à la position sélectionnée
                    if (_selectedPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _selectedPosition!,
                            builder: (ctx) => ScaleTransition(
                              scale: _animation,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: _submitForm,
                child: const Text('Soumettre'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
