import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'connexion.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
  String _title = "Les agressions des derniers 20 jours";
  late MapController _mapController;
  LatLng? _currentLocation;
  late Stream<ServiceStatus> _serviceStatusStream;
  String _pseudo = "Moi"; // Valeur par défaut
  late BuildContext
      dialogContext; // Contexte pour pouvoir fermer le dialogue plus tard

  @override
  void initState() {
    super.initState();
    FirebaseMessaging.instance.subscribeToTopic("all").then((_) {
      print("Abonné au topic 'all'");
    });
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print(
          "Notification reçue en premier plan : ${message.notification?.title}");
    });
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      } else {
        timer.cancel(); // Arrêter le timer si le widget est détruit
      }
    });
    _fetchAgressions();
    _mapController = MapController();
    _checkPermissionAndGetLocation();
    _getUserPseudo();
    _checkInitialLocationStatus();
    _checkInternetConnection(); // Vérification initiale de la connexion

    // Écoute en temps réel si l'utilisateur active la localisation
    _serviceStatusStream = Geolocator.getServiceStatusStream();
    _serviceStatusStream.listen((ServiceStatus status) {
      if (status == ServiceStatus.enabled) {
        _startTracking(); // Démarre le suivi de la position en continu
      } else if (status == ServiceStatus.disabled) {
        setState(() {
          _currentLocation =
              null; // Supprime la position si la localisation est désactivée
        });
        _showTemporaryMessage(
            "Active la localisation pour une meilleure expérience");
      }
    });

    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 1.0, end: 1.5).animate(_controller);

    // Écouter les changements de connectivité en temps réel
    Connectivity().onConnectivityChanged.listen((ConnectivityResult result) {
      if (result == ConnectivityResult.none) {
        _showNoConnectionDialog(); // Afficher le dialogue si la connexion est perdue
      } else {
        if (Navigator.canPop(dialogContext)) {
          Navigator.of(dialogContext)
              .pop(); // Fermer le dialogue si la connexion est rétablie
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Vérifier la connexion Internet au lancement
  void _checkInternetConnection() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult == ConnectivityResult.none) {
      _showNoConnectionDialog();
    }
  }

  // Afficher un dialogue si pas de connexion
  void _showNoConnectionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        dialogContext =
            context; // Sauvegarder le contexte pour pouvoir fermer le dialogue plus tard
        return AlertDialog(
          title: Text("Pas de connexion Internet"),
          content:
              Text("Veuillez vérifier votre connexion Internet et réessayer."),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context)
                    .pop(); // Fermer le dialogue manuellement si l'utilisateur appuie sur "OK"
              },
              child: Text("OK"),
            ),
          ],
        );
      },
    );
  }

  Future<void> sendNotificationToAllUsers() async {
    const String serverKey =
        'VOTRE_CLE_SERVEUR_FCM'; // Remplacez par votre clé serveur FCM

    final Uri url = Uri.parse('https://fcm.googleapis.com/fcm/send');

    final Map<String, dynamic> notificationData = {
      "to":
          "/topics/all", // Envoie à tous les utilisateurs abonnés au topic "all"
      "notification": {
        "title": "Aide urgente demandée !",
        "body":
            "Un utilisateur a besoin d'aide immédiate. Ouvrez l'application pour voir la position.",
        "sound": "default",
      },
      "data": {
        "click_action": "FLUTTER_NOTIFICATION_CLICK",
        "id": "1",
        "status": "done",
        "type":
            "urgent_help", // Ajoutez un type pour identifier la notification
      },
    };

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "key=$serverKey", // Clé serveur FCM
      },
      body: jsonEncode(notificationData),
    );

    if (response.statusCode == 200) {
      print("Notification envoyée avec succès !");
    } else {
      print("Erreur lors de l'envoi de la notification : ${response.body}");
    }
  }

  void _checkInitialLocationStatus() async {
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      _showTemporaryMessage(
          "Active la localisation pour une meilleure expérience");
    }
  }

  Future<void> _checkPermissionAndGetLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      _mapController.move(_currentLocation!, _mapController.zoom);
    } catch (e) {
      print("Erreur lors de l'obtention de la localisation : $e");
    }
  }

  Future<void> _fetchAgressions() async {
    final DateTime now = DateTime.now();
    final DateTime fiveDaysAgo = now.subtract(Duration(days: 20));

    final querySnapshot = await FirebaseFirestore.instance
        .collection('agressions')
        .where('dateAgression',
            isGreaterThanOrEqualTo: fiveDaysAgo
                .toIso8601String()) // 🔹 Filtrer les 5 derniers jours
        .get();

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

  void _showTemporaryMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3), // Disparaît après 3 secondes
      ),
    );
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

bool checkIfUserIsLoggedIn() {
  final user = FirebaseAuth.instance.currentUser;
  return user != null; // Renvoie true si l'utilisateur est connecté, false sinon
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
        final String formattedDate =
            DateFormat('yyyy-MM-dd').format(selectedDate);

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

        _title =
            "Agressions du $formattedDate"; // 🔹 Toujours afficher la date, même si vide
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
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(25)), // Coins arrondis seulement en haut
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(
                      25)), // Applique l'arrondi à l'intérieur aussi
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
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold), // 🔥 Texte en blanc
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
      final index = _filteredAgressions
          .indexWhere((agression) => agression['documentId'] == docId);
      if (index != -1) {
        final agression = _filteredAgressions[index];
        List<dynamic> likedByUser = List.from(agression['likedByUser'] ?? []);
        List<dynamic> dislikedByUser =
            List.from(agression['dislikedByUser'] ?? []);

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
    final docRef =
        FirebaseFirestore.instance.collection('agressions').doc(docId);
    await docRef.update({
      'likedByUser': _filteredAgressions.firstWhere(
          (agression) => agression['documentId'] == docId)['likedByUser'],
      'dislikedByUser': _filteredAgressions.firstWhere(
          (agression) => agression['documentId'] == docId)['dislikedByUser'],
      'likes': _filteredAgressions
          .firstWhere((agression) => agression['documentId'] == docId)['likes'],
      'dislikes': _filteredAgressions.firstWhere(
          (agression) => agression['documentId'] == docId)['dislikes'],
    });
  }

  void _showDetailsDialog(String? date, String? description, String docId,
      int likes, int dislikes, bool userLiked, bool userDisliked) {
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

    bool isLoggedIn = checkIfUserIsLoggedIn(); // Vérifie si l'utilisateur est connecté

void _showLoginDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text("Connexion requise"),
        content: const Text("Vous devez être connecté(e) pour liker ou disliker. Voulez-vous vous connecter maintenant ?"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Ferme le dialogue
            },
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Ferme le dialogue
              // Redirige vers la page de connexion
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
            child: const Text("Se connecter"),
          ),
        ],
      );
    },
  );
}

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
                            if (!isLoggedIn) {
                              _showLoginDialog(context);
                              return;
                            }

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
                        Text('$likes',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            )),
                      ],
                    ),
                    // Bouton de Dislike
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (!isLoggedIn) {
                              _showLoginDialog(context);
                              return;
                            }

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
                        Text('$dislikes',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            )),
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

  Future<void> _getUserPseudo() async {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isNotEmpty) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists) {
        setState(() {
          _pseudo =
              userDoc['pseudo'] ?? 'Moi'; // Si pas de pseudo, on affiche "Moi"
        });
      }
    }
  }

  void _startTracking() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Mise à jour tous les 10 mètres
      ),
    ).listen((Position position) {
      if (position != null) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        // Déplacer la carte vers la nouvelle position
        _mapController.move(_currentLocation!, _mapController.zoom);
      }
    });
  }

  void _showLocationDisabledDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Localisation désactivée"),
          content: Text(
              "Veuillez activer la localisation pour utiliser cette fonctionnalité."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(); // Ferme le dialogue
              },
              child: Text("OK"),
            ),
          ],
        );
      },
    );
  }

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
            color: Colors.white,
            fontSize: 15.0, // Texte en blanc
          ),
        ),
        centerTitle: false,
        actions: [
          Positioned(
            top: 0,
            right: 10,
            child: ElevatedButton(
              onPressed: () {
                bool isLoggedIn = checkIfUserIsLoggedIn(); // Remplace cette fonction par ta propre logique de vérification

    if (isLoggedIn) {
                
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: Text("Aide urgente"),
                      content: Text(
                          "Êtes-vous sûr(e) d'avoir besoin d'une aide urgente ?"),
                      actions: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // Ferme le dialogue
                          },
                          child: Text("Non"),
                        ),
                        TextButton(
                          onPressed: () async {
                            // Vérifie si la localisation est activée
                            bool isLocationEnabled =
                                await Geolocator.isLocationServiceEnabled();
                            if (!isLocationEnabled) {
                              Navigator.of(context).pop();
                              _showLocationDisabledDialog();
                              return; // Arrête l'exécution si la localisation n'est pas activée
                            }

try {
  if (_currentLocation != null) {
    var markerDoc = await FirebaseFirestore.instance.collection('markers').add({
      'location': GeoPoint(_currentLocation!.latitude, _currentLocation!.longitude),
      'timestamp': FieldValue.serverTimestamp(),
      'expiry': Timestamp.fromDate(DateTime.now().add(Duration(minutes: 3600))),
      'pseudo': _pseudo, // Pseudo de l'utilisateur
    });

    // Récupère l'ID du document après son ajout et met à jour
    await markerDoc.update({'id': markerDoc.id});

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Marqueur ajouté sur la carte !")),
    );

    await sendNotificationToAllUsers();
  }
}catch (e) {
                              print("Erreur lors de l'ajout du marqueur : $e");
                            } finally {
                              Navigator.of(context)
                                  .pop(); // Ferme le dialogue quoi qu'il arrive
                            }
                          },
                          child: Text("Oui"),
                        ),
                      ],
                    );
                  },
                );//Showdialogue
                }else {
      // Si l'utilisateur n'est pas connecté, affiche un autre dialogue pour l'orienter vers la page de connexion
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Connexion requise"),
            content: Text("Vous devez être connecté(e) pour demander de l'aide urgente. Voulez-vous vous connecter maintenant ?"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Ferme le dialogue
                },
                child: Text("Annuler"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Ferme le dialogue
                  // Redirige vers la page de connexion
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => LoginPage()), // Remplace LoginPage() par ta page de connexion
                  );
                },
                child: Text("Se connecter"),
              ),
            ],
          );
        },
      );
    }
              }, //Onpressed
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                padding: const EdgeInsets.all(10),
                backgroundColor: Colors.red, // Couleur de fond rouge
              ),
              child: Image.asset(
                'lib/assets/images/urgent.png', // Chemin de l'icône
                width: 24,
                height: 24,
              ),
            ),
          ),
        ],
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
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
              ),
              MarkerLayer(
                markers: [
                  ..._filteredAgressions
                      .where((data) =>
                          data['latitude'] != null && data['longitude'] != null)
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
                          final likedByUser =
                              List<String>.from(data['likedByUser'] ?? []);
                          final dislikedByUser =
                              List<String>.from(data['dislikedByUser'] ?? []);
                          final userId =
                              FirebaseAuth.instance.currentUser?.uid ?? '';
                          final userLiked = likedByUser.contains(userId);
                          final userDisliked = dislikedByUser.contains(userId);
                          _showDetailsDialog(date, description, docId, likes,
                              dislikes, userLiked, userDisliked);
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

                  // Ajout du marqueur de la position actuelle si elle est définie
                  if (_currentLocation != null)
                  Marker(
  point: _currentLocation!,
  width: 50,
  height: 80,
  builder: (ctx) => Transform.translate(
    offset: const Offset(0, -30), // Décale le marqueur vers le haut
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
              ),
            ],
          ),
          child: Flexible(
            child: Text(
              _pseudo, // Affiche le pseudo de l'utilisateur
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
              overflow: TextOverflow.ellipsis, // Ajoute des "..." si le texte est trop long
              maxLines: 1, // Limite le texte à une seule ligne
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: AssetImage("lib/assets/images/person.png"),
              fit: BoxFit.cover,
              colorFilter: ColorFilter.mode(
                Color.fromARGB(255, 11, 72, 122).withOpacity(0.9),
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
      ],
    ),
  ),
)

                ],
              ),
 
StreamBuilder(
  stream: FirebaseFirestore.instance.collection('markers').snapshots(),
  builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return SizedBox(); // Évite de bloquer l'UI
    }

    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
      return SizedBox(); // Pas de marqueurs à afficher
    }
String formatTimeDifference(Timestamp? timestamp) {
  if (timestamp != null) {
    DateTime date = timestamp.toDate();
    DateTime now = DateTime.now();
    
    // Calculer la différence entre l'heure actuelle et le timestamp
    Duration diff = now.difference(date);

    int hours = diff.inHours;
    int minutes = diff.inMinutes % 60; // Les minutes restantes après avoir pris les heures

    // Retourner la chaîne formatée
    return "Ajouté il y a ${hours}h ${minutes}m";
  }
  return "Date inconnue";
}

    // Récupérer l'heure actuelle
    Timestamp now = Timestamp.now();

    // Récupérer le pseudo de l'utilisateur actuel
    String currentUserPseudo = _pseudo;

    // Filtrer les marqueurs qui ont bien le champ "expiry" et ne sont pas expirés
    List<Marker> firebaseMarkers = snapshot.data!.docs
        .where((doc) =>
            doc.data() != null &&
            (doc.data() as Map<String, dynamic>).containsKey('expiry') &&
            doc['expiry'] is Timestamp &&
            doc['expiry'].compareTo(now) > 0)
        .map((doc) {
      var data = doc.data() as Map<String, dynamic>;
      GeoPoint geoPoint = data['location'];
      String pseudo = data['pseudo'] ?? "Utilisateur inconnu"; // Récupérer le pseudo
      String markerId = doc.id; // ID du document Firestore
      Timestamp? timestamp = data['timestamp']; // Récupérer le timestamp du marqueur (peut être nul)
      String timeDifference = formatTimeDifference(timestamp); // Calculer la différence de temps

      return Marker(
        point: LatLng(geoPoint.latitude, geoPoint.longitude),
        width: 80.0, // Largeur du marqueur
        height: 120.0, // Hauteur du marqueur (augmentée pour éviter le débordement)
        builder: (ctx) => GestureDetector(
          onTap: () async {
            if (pseudo == currentUserPseudo) { // Vérifie si le pseudo correspond
              bool? result = await showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text("Supprimer ce marqueur ?"),
                  content: Text("Êtes-vous sûr de vouloir supprimer ce marqueur ?"),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text("Non"),
                    ),
                    TextButton(
                      onPressed: () {
                        FirebaseFirestore.instance.collection('markers').doc(markerId).delete();
                        Navigator.pop(context, true);
                      },
                      child: Text("Oui"),
                    ),
                  ],
                ),
              );

              if (result == true) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Marqueur supprimé !")),
                );
              }
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Vous ne pouvez pas supprimer ce marqueur.")),
              );
            }
          },
          child: Container(
            width: 80.0,
            height: 120.0, // Ajuster la hauteur pour éviter le débordement
            padding: EdgeInsets.all(4), // Ajouter un peu de padding
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning,
                  color: const Color.fromARGB(255, 0, 0, 0),
                  size: 40,
                ),
                SizedBox(height: 4),
                // Utiliser Expanded pour éviter le débordement
                Expanded(
                  child: SingleChildScrollView( // Permettre le défilement si nécessaire
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "$pseudo est en danger",
                          textAlign: TextAlign.center,
                          maxLines: 2, // Limiter à 2 lignes
                          overflow: TextOverflow.ellipsis, // Ajouter "..." si le texte est trop long
                          style: TextStyle(
                            color: const Color.fromARGB(255, 0, 0, 0),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          timeDifference, // Affichage de la différence de temps
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color.fromARGB(255, 0, 0, 0),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();

    return MarkerLayer(markers: firebaseMarkers);
  },
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
                    await _selectDate(
                        context); // Afficher le calendrier pour filtrer les agressions
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Color.fromARGB(255, 11, 72, 122)
                        .withOpacity(0.8), // Couleur de fond
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
                      _title = "Les agressions des derniers 20 jours";
                    });

                    // Recentrer la carte sur Namur
                    _mapController.move(LatLng(50.4675, 4.8711), 13.0);
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(10),
                    backgroundColor: const Color.fromARGB(255, 11, 72, 122)
                        .withOpacity(0.8), // Couleur de fond
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
  onPressed: () async {
    // Vérifie si l'utilisateur est connecté
    bool isLoggedIn = checkIfUserIsLoggedIn();

    if (isLoggedIn) {
      // Si l'utilisateur est connecté, effectue l'action normale (ajouter une agression)
      _addAgression();
    } else {
      // Si l'utilisateur n'est pas connecté, montre le dialogue pour se connecter
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text("Connexion requise"),
            content: Text("Vous devez être connecté(e) pour ajouter une agression. Voulez-vous vous connecter maintenant ?"),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Ferme le dialogue
                },
                child: Text("Annuler"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Ferme le dialogue
                  // Redirige vers la page de connexion
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => LoginPage()),
                  );
                },
                child: Text("Se connecter"),
              ),
            ],
          );
        },
      );
    }
  },
  style: ElevatedButton.styleFrom(
    shape: const CircleBorder(),
    padding: const EdgeInsets.all(10),
    backgroundColor: Color.fromARGB(255, 11, 72, 122).withOpacity(0.8), // Couleur de fond
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
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      isScrollControlled:
                          true, // Permet de contrôler la hauteur
                      builder: (context) {
                        return FractionallySizedBox(
                          heightFactor: 0.2, // 20% de la hauteur de l'écran
                          child: Container(
                            width: double
                                .infinity, // Couvre toute la largeur de l'écran
                            decoration: BoxDecoration(
                              color: Color.fromARGB(
                                  255, 11, 72, 122), // Fond en couleur purple
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  "Contactez-nous",
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors
                                        .white, // Texte en blanc pour contraste
                                  ),
                                ),
                                SizedBox(
                                    height: 10), // Espacement entre les textes
                                Text(
                                  "namursafety@gmail.com",
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors
                                        .white70, // Texte légèrement plus clair
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
                    backgroundColor: Color.fromARGB(255, 11, 72, 122)
                        .withOpacity(0.8), // Couleur de fond
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
                    await FirebaseAuth.instance
                        .signOut(); // Déconnecte l'utilisateur
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              LoginPage()), // Redirige vers LoginPage
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    shape: const CircleBorder(),
                    padding: const EdgeInsets.all(10),
                    backgroundColor: Color.fromARGB(255, 11, 72, 122)
                        .withOpacity(0.8), // Couleur rouge pour la déconnexion
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

  const MainFormPage({Key? key, required this.filteredAgressions})
      : super(key: key);

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

      if (_dateAgression == null ||
          _gravite == null ||
          _selectedPosition == null) {
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
            'position': [
              _selectedPosition!.latitude,
              _selectedPosition!.longitude
            ],
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
        const SnackBar(
            content: Text('Veuillez vérifier les informations fournies')),
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
                            border: Border(
                                bottom:
                                    BorderSide(color: Colors.grey.shade400)),
                          ),
                          child: Text(
                            _dateAgression != null
                                ? DateFormat('dd/MM/yyyy')
                                    .format(_dateAgression!)
                                : 'Sélectionnez une date',
                            style: const TextStyle(
                                fontSize: 16,
                                color: Colors.white), // 🔥 Texte en blanc
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
                                color: _gravite == value
                                    ? Colors.white
                                    : Color.fromARGB(255, 11, 72,
                                        122), // Si la gravité est sélectionnée, texte en blanc, sinon en violet
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
                            color: _wordCount > 50
                                ? Colors.red
                                : Colors.white, // 🔥 Texte blanc ou rouge
                          ),
                        ),
                      ),
                      const SizedBox(height: 16.0),
                      ElevatedButton(
                        onPressed: _openMapForSelection,
                        child: const Text(
                            'Sélectionner une position sur la carte'),
                      ),
                      if (_selectedPosition != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: const Text(
                            '               Position sélectionnée ',
                            style: TextStyle(
                                fontSize: 16,
                                color: Colors.white), // 🔥 Texte en blanc
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
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
      labelStyle: TextStyle(color: Colors.white, fontSize: 16),
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
  LatLng? _currentLocation;
  late Stream<ServiceStatus> _serviceStatusStream;
  String _pseudo = "Moi";
  late MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _checkPermissionAndGetLocation();
    _serviceStatusStream = Geolocator.getServiceStatusStream();
    _serviceStatusStream.listen((ServiceStatus status) {
      if (status == ServiceStatus.enabled) {
        _startTracking(); // Démarre le suivi de la position en continu
      } else if (status == ServiceStatus.disabled) {
        setState(() {
          _currentLocation =
              null; // Supprime la position si la localisation est désactivée
        });
      }
    });
  }

  void _checkInitialLocationStatus() async {
    bool isLocationEnabled = await Geolocator.isLocationServiceEnabled();
    if (!isLocationEnabled) {
      _showTemporaryMessage(
          "Active la localisation pour une meilleure expérience");
    }
  }

  Future<void> _checkPermissionAndGetLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }

    _getCurrentLocation();
  }

  void _showTemporaryMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: 3), // Disparaît après 3 secondes
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      _mapController.move(_currentLocation!, _mapController.zoom);
    } catch (e) {
      print("Erreur lors de l'obtention de la localisation : $e");
    }
  }

  Future<void> _getUserPseudo() async {
    String userId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (userId.isNotEmpty) {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (userDoc.exists) {
        setState(() {
          _pseudo =
              userDoc['pseudo'] ?? 'Moi'; // Si pas de pseudo, on affiche "Moi"
        });
      }
    }
  }

  void _startTracking() {
    Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Mise à jour tous les 10 mètres
      ),
    ).listen((Position position) {
      if (position != null) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });

        // Déplacer la carte vers la nouvelle position
        _mapController.move(_currentLocation!, _mapController.zoom);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner une position'),
        automaticallyImplyLeading: false,
      ),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(50.4675, 4.8711),
          zoom: 13.0,
          minZoom: 10.0, // 🔹 Zoom minimum autorisé
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
          // Affichage du marqueur de la position actuelle de l'utilisateur
          if (_currentLocation != null)
            MarkerLayer(
              markers: [
                Marker(
                  point: _currentLocation!,
                  width: 50,
                  height: 80,
                  builder: (ctx) => Transform.translate(
                    offset:
                        const Offset(0, -30), // Décale le marqueur vers le haut
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Affichage du pseudo
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: Text(
                            _pseudo, // Affiche le pseudo de l'utilisateur
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Affichage de l'image
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: AssetImage("lib/assets/images/person.png"),
                              fit: BoxFit.cover,
                              colorFilter: ColorFilter.mode(
                                  Color.fromARGB(255, 11, 72, 122)
                                      .withOpacity(0.9),
                                  BlendMode.srcIn),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          // Affichage du marqueur de la position sélectionnée, si définie
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
