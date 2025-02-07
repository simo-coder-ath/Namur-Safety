import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'connexion.dart';

// Remplace par le bon chemin




class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  _MapPageState createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _agressions = [];
  final List<Map<String, dynamic>> _filteredAgressions = [];
  late AnimationController _controller;
  late Animation<double> _animation;
  Set<String> _votedDocs = {}; 
  String _title = "Toutes les agressions";
  final MapController _mapController = MapController();

 // Pour suivre les agressions déjà votées

  @override
  void initState() {
    super.initState();
    _fetchAgressions();

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.5).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
 
Future<void> _fetchAgressions() async {
  final querySnapshot =
      await FirebaseFirestore.instance.collection('agressions').get();

  setState(() {
    _agressions.clear(); // 🔥 Évite les doublons
    _filteredAgressions.clear();

    _agressions.addAll(querySnapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      double? latitude;
      double? longitude;

      if (data['position'] != null && data['position'] is List) {
        latitude = (data['position'][0] as num).toDouble();
        longitude = (data['position'][1] as num).toDouble();
      }

      return {
        ...data,
        'latitude': latitude,
        'longitude': longitude,
        'documentId': doc.id, // Ajout de l'ID du document
      };
    }).toList());

    _filteredAgressions.addAll(_agressions);
  });
}

  
  


  Future<void> _selectDate(BuildContext context) async {
    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
  
    if (selectedDate != null) {
      _filterAgressionsByDate(selectedDate);
    }
  }

void _filterAgressionsByDate(DateTime? selectedDate) {
  setState(() {
    _filteredAgressions.clear();

    if (selectedDate == null) {
      // Cas où l'utilisateur veut afficher toutes les agressions
      _filteredAgressions.addAll(_agressions);
      _title = "Toutes les agressions"; // 🔹 Mise à jour correcte du titre
    } else {
      // Cas où l'utilisateur sélectionne une date spécifique
      final String formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);

      _filteredAgressions.addAll(_agressions.where((agression) {
        final dateAgression = agression['dateAgression'] as String?;
        if (dateAgression == null) return false;

        try {
          final String agressionDate =
              DateFormat('yyyy-MM-dd').format(DateTime.parse(dateAgression));
          return agressionDate == formattedDate;
        } catch (e) {
          return false;
        }
      }).toList());

      _title = "Agressions du $formattedDate"; // 🔹 Toujours afficher la date, même si vide
    }
  });
}



void _addAgression() async {
  final result = await showModalBottomSheet(
    context: context,
    isScrollControlled: true, // Permet d'ajuster la hauteur du modal
    backgroundColor: Colors.transparent, // Permet de gérer le border radius
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.7, // Définit la hauteur à 60% de l'écran
        child: Container(
          width: double.infinity, // Prend toute la largeur
          decoration: BoxDecoration(
            color: Colors.white, // Fond du formulaire
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)), // Coins arrondis seulement en haut
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)), // Applique l'arrondi à l'intérieur aussi
            child: MainFormPage(filteredAgressions: _filteredAgressions),
          ),
        ),
      );
    },
  );
    
  if (result == true) {
    
    
    _showSubmissionDialog();
    setState(() {
      _fetchAgressions(); 
    });
  }
}

void _showSubmissionDialog() {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        backgroundColor: Color.fromARGB(255, 11, 72, 122), // 🟣 Fond violet
        title: const Text(
          "Agression enregistrée",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), // 🔥 Texte en blanc
        ),
        content: const Text(
          "Votre agression a bien été enregistrée.",
          style: TextStyle(color: Colors.white), // 🔥 Texte en blanc
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text(
              "OK",
              style: TextStyle(color: Colors.white), // 🔥 Bouton en blanc
            ),
          ),
        ],
      );
    },
  );
}



Future<void> _updateLikesDislikes(String docId, bool isLike) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;

  setState(() {
    final index = _filteredAgressions.indexWhere((agression) => agression['documentId'] == docId);
    if (index != -1) {
      final agression = _filteredAgressions[index];
      List<dynamic> likedByUser = List.from(agression['likedByUser'] ?? []);
      List<dynamic> dislikedByUser = List.from(agression['dislikedByUser'] ?? []);

      if (isLike) {
        if (likedByUser.contains(userId)) {
          // Annuler le Like
          likedByUser.remove(userId);
          agression['likes'] = (agression['likes'] ?? 0) - 1;
        } else {
          // Ajouter un Like
          likedByUser.add(userId);
          agression['likes'] = (agression['likes'] ?? 0) + 1;

          // Supprimer un Dislike si présent
          if (dislikedByUser.contains(userId)) {
            dislikedByUser.remove(userId);
            agression['dislikes'] = (agression['dislikes'] ?? 0) - 1;
          }
        }
      } else {
        if (dislikedByUser.contains(userId)) {
          // Annuler le Dislike
          dislikedByUser.remove(userId);
          agression['dislikes'] = (agression['dislikes'] ?? 0) - 1;
        } else {
          // Ajouter un Dislike
          dislikedByUser.add(userId);
          agression['dislikes'] = (agression['dislikes'] ?? 0) + 1;

          // Supprimer un Like si présent
          if (likedByUser.contains(userId)) {
            likedByUser.remove(userId);
            agression['likes'] = (agression['likes'] ?? 0) - 1;
          }
        }
      }

      agression['likedByUser'] = likedByUser;
      agression['dislikedByUser'] = dislikedByUser;
    }
  });

  // Mise à jour de Firestore après le rendu
  final docRef = FirebaseFirestore.instance.collection('agressions').doc(docId);
  await docRef.update({
    'likedByUser': _filteredAgressions.firstWhere((agression) => agression['documentId'] == docId)['likedByUser'],
    'dislikedByUser': _filteredAgressions.firstWhere((agression) => agression['documentId'] == docId)['dislikedByUser'],
    'likes': _filteredAgressions.firstWhere((agression) => agression['documentId'] == docId)['likes'],
    'dislikes': _filteredAgressions.firstWhere((agression) => agression['documentId'] == docId)['dislikes'],
  });
}


void _showDetailsDialog(String? date, String? description, String docId, int likes, int dislikes, bool userLiked, bool userDisliked) {
  String safeDate;
  if (date != null) {
    try {
      final parsedDate = DateTime.parse(date);
      safeDate = DateFormat('dd/MM/yyyy').format(parsedDate);
    } catch (e) {
      safeDate = 'Date invalide';
    }
  } else {
    safeDate = 'Date inconnue';
  }

  final safeDescription = description ?? 'Pas de description fournie';

  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.7),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20.0),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Détails de l\'agression',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Le $safeDate',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    ' $safeDescription',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 40),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Bouton de Like
                      Row(
                        children: [
                          GestureDetector(
                           onTap: () {
  setState(() {
    if (userLiked) {
      // Annuler le Like
      likes--;
      userLiked = false;
    } else {
      // Ajouter un Like
      likes++;
      userLiked = true;
      if (userDisliked) {
        dislikes--;
        userDisliked = false;
      }
    }
  });
  _updateLikesDislikes(docId, true);
},

                            child: Icon(
                              Icons.thumb_up,
                              size: 30,
                              color: userLiked ? Colors.green : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$likes', style: const TextStyle(fontSize: 16, color: Colors.white,)),
                        ],
                      ),
                      // Bouton de Dislike
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                if (userDisliked) {
      // Annuler le Dislike
      dislikes--;
      userDisliked = false;
    } else {
      // Ajouter un Dislike
      dislikes++;
      userDisliked = true;
      if (userLiked) {
        likes--;
        userLiked = false;
      }
    }
  });
  _updateLikesDislikes(docId, false);
},
                            child: Icon(
                              Icons.thumb_down,
                              size: 30,
                              color: userDisliked ? Colors.red : Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('$dislikes', style: const TextStyle(fontSize: 16, color: Colors.white,)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(),   
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}


 @override
@override
Widget build(BuildContext context) {
  final LatLng namurCoordinates = LatLng(50.4675, 4.8711);
  double zoom = 13.0;

  return Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8),
  title: Text(
    _title,
    style: TextStyle(
      
      color: Colors.white, // Texte en blanc
    ),
  ),
  centerTitle: true,
),
    body: Stack(
      children: [
        FlutterMap(
  mapController: _mapController, // 🔹 Ajout du contrôleur ici
  options: MapOptions(
    center: namurCoordinates,
    zoom: zoom,
    minZoom: 10.0,
    maxZoom: 16.0,
  ),
  children: [
    TileLayer(
      urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'],
    ),
    MarkerLayer(
      markers: _filteredAgressions
          .where((data) => data['latitude'] != null && data['longitude'] != null)
          .map((data) {
        return Marker(
          point: LatLng(data['latitude'], data['longitude']),
          builder: (ctx) => GestureDetector(
            onTap: () {
              final date = data['dateAgression'] as String?;
              final description = data['description'] as String?;
              final docId = data['documentId'] as String;
              final likes = data['likes'] ?? 0;
              final dislikes = data['dislikes'] ?? 0;
              final likedByUser = List<String>.from(data['likedByUser'] ?? []);
              final dislikedByUser = List<String>.from(data['dislikedByUser'] ?? []);
              final userId = FirebaseAuth.instance.currentUser?.uid ?? '';
              final userLiked = likedByUser.contains(userId);
              final userDisliked = dislikedByUser.contains(userId);
              _showDetailsDialog(date, description, docId, likes, dislikes, userLiked, userDisliked);
            },
            child: ScaleTransition(
              scale: _animation,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withOpacity(0.7),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    ),
  ],
),

        Positioned(
          bottom: 25,
          left: 20,
          child: Row(
            children: [
              // Bouton Filtrer
              ElevatedButton(
                onPressed: () async {
                  await _selectDate(context); // Afficher le calendrier pour filtrer les agressions
                },
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(10),
                  backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8), // Couleur de fond
                ),
                child: const Icon(
                  Icons.filter_alt, // Icône de filtre
                  color: Colors.white, // Couleur de l'icône
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),

              // Bouton Afficher tout
              ElevatedButton(
  onPressed: () {
    setState(() {
      // Réinitialiser les agressions filtrées avec toutes les agressions
      _filteredAgressions.clear();
      _filteredAgressions.addAll(_agressions);
      _title = "Toutes les agressions";
    });

    // Recentrer la carte sur Namur
    _mapController.move(LatLng(50.4675, 4.8711), 13.0);
  },
  style: ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    padding: const EdgeInsets.all(10),
    backgroundColor: const Color.fromARGB(255, 11, 72, 122).withOpacity(0.8), // Couleur de fond
  ),
  child: const Icon(
    Icons.map, // Icône pour afficher toutes les agressions
    color: Colors.white, // Couleur de l'icône
    size: 24,
  ),
),

              const SizedBox(width: 10),

              // Bouton Ajouter une agression
              ElevatedButton(
                onPressed: _addAgression,
                style: ElevatedButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(10),
                  backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8) // Couleur de fond
                ),
                child: const Icon(
                  Icons.add, // Icône "plus" pour ajouter une agression
                  color: Colors.white, // Couleur de l'icône
                  size: 24, // Taille de l'icône
                ),
              ),

              const SizedBox(width: 10),
// Bouton Mail
ElevatedButton(
  onPressed: () {
  showModalBottomSheet(
  context: context,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  isScrollControlled: true, // Permet de contrôler la hauteur
  builder: (context) {
    return FractionallySizedBox(
      heightFactor: 0.2, // 20% de la hauteur de l'écran
      child: Container(
        width: double.infinity, // Couvre toute la largeur de l'écran
        decoration: BoxDecoration(
          color: Color.fromARGB(255, 11, 72, 122), // Fond en couleur purple
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Contactez-nous",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white, // Texte en blanc pour contraste
              ),
            ),
            SizedBox(height: 10), // Espacement entre les textes
            Text(
              "namursafety@gmail.com",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white70, // Texte légèrement plus clair
              ),
            ),
          ],
        ),
      ),
    );
  },
);

  },
  style: ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    padding: const EdgeInsets.all(10),
    backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8), // Couleur de fond
  ),
  child: const Icon(
    Icons.mail, // Icône de mail
    color: Colors.white, // Couleur de l'icône
    size: 24,
  ),
),

const SizedBox(width: 10),

// Bouton Déconnexion
ElevatedButton(
  onPressed: () async {
    await FirebaseAuth.instance.signOut(); // Déconnecte l'utilisateur
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()), // Redirige vers LoginPage
    );
  },
  style: ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    padding: const EdgeInsets.all(10),
    backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8), // Couleur rouge pour la déconnexion
  ),
  child: const Icon(
    Icons.logout, // Icône de déconnexion
    color: Colors.white,
    size: 24,
  ),
),




            ],
          ),
        ),
      ],
    ),
  );
}



}









class MainFormPage extends StatefulWidget {
  final List<Map<String, dynamic>> filteredAgressions;

  const MainFormPage({Key? key, required this.filteredAgressions}) : super(key: key);

  @override
  _MainFormPageState createState() => _MainFormPageState();
}

class _MainFormPageState extends State<MainFormPage> {
  final _formKey = GlobalKey<FormState>();
  DateTime? _dateAgression;
  String? _gravite;
  String? _description;
  LatLng? _selectedPosition; // La position sélectionnée
  int _wordCount = 0; // Compteur de mots

  final List<String> _graviteOptions = ['Faible', 'Moyenne', 'Élevée'];

  // Nouvelle méthode pour compter les mots
  int _calculateWordCount(String text) {
    return text.split(RegExp(r'\s+')).where((word) => word.isNotEmpty).length;
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

  Future<void> _openMapForSelection() async {
    final LatLng? selected = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SelectLocationPage()),
    );
    if (selected != null) {
      setState(() {
        _selectedPosition = selected;
      });
    }
  }
Future<void> _submitForm() async { 
  if (_formKey.currentState!.validate()) {
    _formKey.currentState!.save();

    if (_wordCount > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La description ne peut pas dépasser 50 mots'),
        ),
      );
      return;
    }

    if (_dateAgression == null || _gravite == null || _selectedPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez remplir tous les champs requis'),
        ),
      );
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        await FirebaseFirestore.instance.collection('agressions').add({
          'userId': user.uid,
          'userEmail': user.email,
          'dateAgression': _dateAgression?.toIso8601String(),
          'gravite': _gravite,
          'description': _description,
          'position': [_selectedPosition!.latitude, _selectedPosition!.longitude],
          'createdAt': DateTime.now(),
        });

        // Réinitialiser le formulaire
        _formKey.currentState!.reset();
        setState(() {
          _dateAgression = null;
          _gravite = null;
          _description = null;
          _selectedPosition = null;
          _wordCount = 0;
        });

        // Redirection vers la page MapPageState
        Navigator.pop(context, true);

        // Affichage du dialogue après un court délai pour s'assurer que la page est chargée
        Future.delayed(const Duration(milliseconds: 500), () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Succès'),
                content: const Text('Agression ajoutée avec succès'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('OK'),
                  ),
                ],
              );
            },
          );
        });

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur : utilisateur non connecté')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors de l\'enregistrement : $e')),
      );
    }
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Veuillez vérifier les informations fournies')),
    );
  }
}


  
 @override
Widget build(BuildContext context) {
  return Scaffold(
    resizeToAvoidBottomInset: true,
    body: Container(
      color: Color.fromARGB(255, 11, 72, 122), // 🟣 Fond violet unifié
      child: Column(
        children: [
         AppBar(
  automaticallyImplyLeading: false,
  title: const Text(
    'Ajouter Agression',
    style: TextStyle(
      color: Colors.white, // 🔥 Texte en blanc
      fontWeight: FontWeight.bold, // 🔥 Texte en gras
    ),
  ),
  backgroundColor: Colors.transparent, // Garde le fond transparent
  elevation: 0,
),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    GestureDetector(
                      onTap: () => _selectDate(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
                        ),
                        child: Text(
                          _dateAgression != null
                              ? DateFormat('dd/MM/yyyy').format(_dateAgression!)
                              : 'Sélectionnez une date',
                          style: const TextStyle(fontSize: 16, color: Colors.white), // 🔥 Texte en blanc
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    DropdownButtonFormField<String>(
  decoration: _inputDecoration('Gravité'),
  value: _gravite,
  items: _graviteOptions.map((String value) {
    return DropdownMenuItem<String>(
      value: value,
      child: Text(
        value,
        style: TextStyle(
          color: _gravite == value ? Colors.white : Color.fromARGB(255, 11, 72, 122), // Si la gravité est sélectionnée, texte en blanc, sinon en violet
        ),
      ),
    );
  }).toList(),
  onChanged: (newValue) {
    setState(() {
      _gravite = newValue;
    });
  },
),

                    _buildTextField(
                      'Description',
                      onSaved: (value) => _description = value,
                      maxLines: 3,
                      onChanged: (value) {
                        setState(() {
                          _description = value;
                          _wordCount = _calculateWordCount(value);
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        'Nombre de mots : $_wordCount/50',
                        style: TextStyle(
                          color: _wordCount > 50 ? Colors.red : Colors.white, // 🔥 Texte blanc ou rouge
                        ),
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    ElevatedButton(
                      onPressed: _openMapForSelection,
                      child: const Text('Sélectionner une position sur la carte'),
                    ),
                    if (_selectedPosition != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: const Text(
                          '               Position sélectionnée ',
                          style: TextStyle(fontSize: 16, color: Colors.white), // 🔥 Texte en blanc
                        ),
                      ),
                    const SizedBox(height: 24.0),
                    ElevatedButton(
                      onPressed: _submitForm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text(
                        'Soumettre',
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}


  Widget _buildTextField(
  String label, {
  required FormFieldSetter<String> onSaved,
  int maxLines = 1,
  ValueChanged<String>? onChanged,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20.0),
    child: TextFormField(
      decoration: _inputDecoration(label),
      onSaved: onSaved,
      onChanged: onChanged,
      maxLines: maxLines,
      style: TextStyle(color: Colors.white), // Texte affiché en blanc
    ),
  );
}


  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white , fontSize: 16),
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.grey),
      ),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.teal),
      ),
    );
  }
}



class SelectLocationPage extends StatefulWidget {
  const SelectLocationPage({super.key});

  @override
  _SelectLocationPageState createState() => _SelectLocationPageState();
}

class _SelectLocationPageState extends State<SelectLocationPage> {
  LatLng? _selectedPosition;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sélectionner une position'),automaticallyImplyLeading: false),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(50.4675, 4.8711),
          zoom: 13.0,
          minZoom: 10.0,  // 🔹 Zoom minimum autorisé
          maxZoom: 16.0,
          onTap: (tapPosition, latLng) {
            setState(() {
              _selectedPosition = latLng;
            });
          },
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: ['a', 'b', 'c'],
          ),
          if (_selectedPosition != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _selectedPosition!,
                  builder: (ctx) => const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.pop(context, _selectedPosition);
        },
        child: const Icon(Icons.check),
      ),
    );
  }
}











































