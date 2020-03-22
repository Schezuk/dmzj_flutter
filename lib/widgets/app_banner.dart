import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dmzj/views/news/news_detail.dart';

class AppBanner extends StatefulWidget {
  List<Widget> items = [];
  int currentBannerIndex = 0;
  AppBanner({Key key, this.items}) : super(key: key);

  _AppBannerState createState() => _AppBannerState();
}

class _AppBannerState extends State<AppBanner> {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8),
      child: Stack(
      alignment: AlignmentDirectional.bottomEnd,
      children: <Widget>[
        ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:CarouselSlider(
          onPageChanged: (i) {
            setState(() {
              widget.currentBannerIndex = i;
            });
          },
          aspectRatio: 7.5 / 4,
          viewportFraction: 1.0,
          autoPlay: true,
          items: widget.items.length != 0
              ? widget.items
              : [
                  Center(
                    child: CircularProgressIndicator(),
                  )
                ],
        )),
        Positioned(
            right: 8.0,
            bottom: 4.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: widget.items.map<Widget>((index) {
                return Container(
                  width: 8.0,
                  height: 8.0,
                  margin: EdgeInsets.symmetric(vertical: 10.0, horizontal: 2.0),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.currentBannerIndex ==
                              widget.items.indexOf(index)
                          ? Theme.of(context).accentColor
                          : Color.fromRGBO(0, 0, 0, 0.4)),
                );
              }).toList(),
            ))
      ],
    ),
    );
  }
}

class BannerImageItem extends StatelessWidget {
  String pic = "";
  Function onTaped;
  String title = "";
  BannerImageItem({Key key, this.pic, this.onTaped, this.title = ""})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTaped,
      child: Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: <Widget>[
          CachedNetworkImage(
            imageUrl: pic,
             httpHeaders: {
                "Referer":"http://www.dmzj.com/"
              },
            placeholder: (context, url) => Center(
              child: Center(child: Icon(Icons.photo)),
            ),
            errorWidget: (context, url, error) =>
                Center(child: Icon(Icons.error)),
          ),
          Positioned(
              child: Container(
            padding: EdgeInsets.all(8),
            width: double.infinity,
            child: Text(title,
                style: TextStyle(
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      blurRadius: 6.0,
                      color: Colors.black26,
                      offset: Offset(2.0, 2.0),
                    ),
                  ],
                )),
          ))
        ],
      ),
    );
  }
}
