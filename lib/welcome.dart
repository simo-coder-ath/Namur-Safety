import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'connexion.dart'; 
import 'firstpage.dart';
import 'dart:ui' as ui;
// Importez la page de connexion ici


import 'package:flutter/material.dart';
import 'package:flutter/material.dart';


class AnimatedTextPage extends StatefulWidget {
  @override
  _AnimatedTextPageState createState() => _AnimatedTextPageState();
}

class _AnimatedTextPageState extends State<AnimatedTextPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<int> _textAnimation;
  bool _showText = false; // Contrôler l'affichage du texte

  final String _text = "Namur Safety"; // Le texte à afficher

  @override
  void initState() {
    super.initState();

    // Animation pour l'échelle de l'image
    _controller = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.1, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Animation pour l'affichage du texte lettre par lettre
    _textAnimation = IntTween(begin: 0, end: _text.length).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    // Lancer l'animation de l'image
    _controller.forward();

    // Après que l'animation de l'image soit terminée, attendre 3 secondes avant de montrer le texte
    Future.delayed(Duration(seconds: 2), () {
      Future.delayed(Duration(seconds: 1), () {
        setState(() {
          _showText = true; // Afficher le texte après une pause de 3 secondes
        });
        _controller.forward(); // Lancer l'animation du texte
      });
    });

    // Après que le texte soit affiché pendant 2 secondes, naviguer vers MyApp
    Future.delayed(Duration(seconds: 5), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => MapPage()), // Remplacer par ta page MyApp
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Animation pour l'image
            ScaleTransition(
              scale: _scaleAnimation,
              child: Image.asset(
                'lib/assets/images/log_app.PNG', // Remplacer par le chemin de votre logo
                fit: BoxFit.contain,
              ),
            ),
            // Afficher le texte après un délai de 3 secondes
            if (_showText)
              Align(
                alignment: Alignment.bottomCenter, // Aligner le texte en bas
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 200), // Ajuste la distance du bas
                  child: AnimatedBuilder(
                    animation: _textAnimation,
                    builder: (context, child) {
                      // Créer le texte animé, en affichant progressivement les lettres
                      String animatedText = _text.substring(0, _textAnimation.value);
                      return Text(
                        animatedText,
                        style: TextStyle(
                          fontFamily: 'YangBagus', // Appliquer la police personnalisée
                          fontSize: 32.0,
                          fontWeight: FontWeight.bold, // Texte en gras
                          color: Color.fromARGB(255, 11, 72, 122), // Couleur du texte en bleu
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
