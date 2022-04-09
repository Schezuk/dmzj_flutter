import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:battery/battery.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_dmzj/app/api/novel.dart';
import 'package:flutter_dmzj/app/app_setting.dart';
import 'package:flutter_dmzj/app/config_helper.dart';
import 'package:flutter_dmzj/app/user_helper.dart';
import 'package:flutter_dmzj/app/user_info.dart';
import 'package:flutter_dmzj/app/utils.dart';
import 'package:flutter_dmzj/models/novel/novel_volume_item.dart';
import 'package:flutter_dmzj/sql/novel_history.dart';
import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:flutter_android_volume_keydown/flutter_android_volume_keydown.dart';

class NovelReaderPage extends StatefulWidget {
  final int novelId;
  final String novelTitle;
  final List<NovelVolumeChapterItem> chapters;
  final NovelVolumeChapterItem currentItem;
  bool subscribe;
  NovelReaderPage(
      this.novelId, this.novelTitle, this.chapters, this.currentItem,
      {this.subscribe, Key key})
      : super(key: key);

  @override
  _NovelReaderPageState createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  //EventBus settingEvent = EventBus();
  List<String> _pageContents = ["加载中"];
  NovelVolumeChapterItem _currentItem;
  Battery _battery = Battery();
  Uint8List _contents;

  double _verSliderMax = 0;
  double _verSliderValue = 0;

  double _fontSize = 16.0;
  double _lineHeight = 1.5;
  String _batteryStr = "-%";
  String _timeStr = "00:00"; // 时间显示
  @override
  void initState() {
    super.initState();
    _currentItem = widget.currentItem;
    //全屏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
    _battery.batteryLevel.then((e) {
      setState(() {
        _batteryStr = e.toString() + "%";
        DateTime now = DateTime.now();
        _timeStr = DateFormat('HH:mm').format(now);
      });
    });

    _battery.onBatteryStateChanged.listen((BatteryState state) async {
      var e = await _battery.batteryLevel;
      setState(() {
        _batteryStr = e.toString() + "%";
        DateTime now = DateTime.now();
        _timeStr = DateFormat('HH:mm').format(now);
      });
    });

    //定时器
    Timer.periodic(Duration(minutes: 1), (timer) {
      if (!mounted) {
        return;
      }

      setState(() {
        DateTime now = DateTime.now();
        _timeStr = DateFormat('HH:mm').format(now);
      });
    });

    //刷新内容
    // settingEvent.on<double>().listen((e) async {
    //   await handelContent();
    // });

    // _controller.addListener((){
    //   print(_controller.offset);
    // });
    _controllerVer.addListener(() {
      var value = _controllerVer.offset;
      if (value < 0) {
        value = 0;
      }
      if (value > _controllerVer.position.maxScrollExtent) {
        value = _controllerVer.position.maxScrollExtent;
      }
      setState(() {
        _verSliderMax = _controllerVer.position.maxScrollExtent;
        _verSliderValue = value;
      });
    });

    loadData();
    startListening();
  }

  @override
  void dispose() {
    SystemChrome.restoreSystemUIOverlays();

    NovelHistoryProvider.updateOrCreate(NovelHistory(
        widget.novelId, _currentItem.chapter_id, _indexPage.toDouble(), 1));

    UserHelper.comicAddNovelHistory(
        widget.novelId, _currentItem.volume_id, _currentItem.chapter_id,
        page: _indexPage);
    subscription?.cancel();
    super.dispose();
  }

  @override
  void setState(fn) {
    if (mounted) {
      super.setState(fn);
    }
  }

  void startListening() {
    subscription = FlutterAndroidVolumeKeydown.stream.listen((event) {
      if (event == HardwareButton.volume_down) {
        print("Volume down received");
        nextPage();
      } else if (event == HardwareButton.volume_up) {
        print("Volume up received");
        previousPage();
      }
    });
  }

  bool _showControls = false;
  bool _showChapters = false;
  PageController _controller = PageController(initialPage: 1);
  ScrollController _controllerVer = ScrollController();
  int _indexPage = 1;
  bool _isPicture = false;

  StreamSubscription<HardwareButton> subscription;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          AppSetting.bgColors[Provider.of<AppSetting>(context).novelReadTheme],
      body: Stack(
        children: <Widget>[
          InkWell(
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            onTap: () {
              setState(() {
                if (_showChapters) {
                  _showChapters = false;
                  return;
                }
                _showControls = !_showControls;
              });
            },
            child: Provider.of<AppSetting>(context).novelReadDirection != 2
                ? PageView.builder(
                    scrollDirection: Axis.horizontal,
                    pageSnapping:
                        Provider.of<AppSetting>(context).novelReadDirection !=
                            2,
                    controller: _controller,
                    itemCount: _pageContents.length + 2,
                    reverse:
                        Provider.of<AppSetting>(context).novelReadDirection ==
                            1,
                    onPageChanged: (int page) {
                      if (page == _pageContents.length + 1 && !_loading) {
                        nextChapter();
                        return;
                      }
                      if (page == 0 && !_loading) {
                        print("slide previous page:$page");
                        previousChapter();
                        return;
                      }
                      if (page < _pageContents.length + 1) {
                        setState(() {
                          // print("setState page:$page");
                          // print("setState indexPage:$_indexPage");
                          _indexPage = page;
                          NovelHistoryProvider.updateOrCreate(NovelHistory(
                              widget.novelId,
                              _currentItem.chapter_id,
                              page.toDouble(),
                              1));
                          // ConfigHelper.setCurrentPage(
                          //     widget.novelId, _currentItem.chapter_id, i);
                        });
                      }
                    },
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return Container(
                          child: Center(
                              child: Text("上一章",
                                  style: TextStyle(color: Colors.grey))),
                        );
                      }
                      if (i == _pageContents.length + 1) {
                        return Container(
                          child: Center(
                              child: Text("下一章",
                                  style: TextStyle(color: Colors.grey))),
                        );
                      }

                      var _widget = _isPicture
                          ? Container(
                              color: AppSetting.bgColors[
                                  Provider.of<AppSetting>(context)
                                      .novelReadTheme],
                              child: InkWell(
                                onDoubleTap: () {
                                  Utils.showImageViewDialog(
                                      context,
                                      _pageContents.length == 0
                                          ? ""
                                          : _pageContents[i - 1]);
                                },
                                onTap: () {
                                  setState(() {
                                    if (_showChapters) {
                                      _showChapters = false;
                                      return;
                                    }
                                    _showControls = !_showControls;
                                  });
                                },
                                child: Utils.createCacheImage(
                                    _pageContents[i - 1], 100, 100,
                                    fit: BoxFit.fitWidth),
                              ),
                            )
                          : Container(
                              color: AppSetting.bgColors[
                                  Provider.of<AppSetting>(context)
                                      .novelReadTheme],
                              padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
                              alignment: Alignment.topCenter,
                              child: Text(
                                _pageContents.length == 0
                                    ? ""
                                    : _pageContents[i - 1],
                                style: TextStyle(
                                    fontSize: _fontSize,
                                    height: _lineHeight,
                                    color: AppSetting.fontColors[
                                        Provider.of<AppSetting>(context)
                                            .novelReadTheme]),
                              ),
                            );
                      return _widget;
                    },
                  )
                : EasyRefresh(
                    onRefresh: () async {
                      previousChapter();
                    },
                    onLoad: () async {
                      nextChapter();
                    },
                    header: MaterialHeader(),
                    footer: MaterialFooter(),
                    child: SingleChildScrollView(
                      controller: _controllerVer,
                      child: _isPicture
                          ? Column(
                              children: _pageContents
                                  .map((f) => InkWell(
                                        onDoubleTap: () {
                                          Utils.showImageViewDialog(context, f);
                                        },
                                        onTap: () {
                                          setState(() {
                                            if (_showChapters) {
                                              _showChapters = false;
                                              return;
                                            }
                                            _showControls = !_showControls;
                                          });
                                        },
                                        child:
                                            Utils.createCacheImage(f, 100, 100),
                                      ))
                                  .toList(),
                            )
                          : Container(
                              alignment: Alignment.topCenter,
                              constraints: BoxConstraints(
                                minHeight: MediaQuery.of(context).size.height,
                              ),
                              color: AppSetting.bgColors[
                                  Provider.of<AppSetting>(context)
                                      .novelReadTheme],
                              padding: EdgeInsets.fromLTRB(12, 12, 12, 24),
                              child: Text(_pageContents.join(),
                                  style: TextStyle(
                                      fontSize: _fontSize,
                                      height: _lineHeight,
                                      color: AppSetting.fontColors[
                                          Provider.of<AppSetting>(context)
                                              .novelReadTheme])),
                            ),
                    ),
                  ),
          ),
          Provider.of<AppSetting>(context).novelReadDirection == 2
              ? Positioned(child: Container())
              : Positioned(
                  left: 0,
                  width: 40,
                  height: MediaQuery.of(context).size.height,
                  child: InkWell(
                    onTap: () {
                      if (Provider.of<AppSetting>(context, listen: false)
                              .novelReadDirection ==
                          1) {
                        nextPage();
                      } else {
                        previousPage();
                      }
                    },
                    child: Container(),
                  ),
                ),
          Provider.of<AppSetting>(context).novelReadDirection == 2
              ? Positioned(child: Container())
              : Positioned(
                  right: 0,
                  width: 40,
                  height: MediaQuery.of(context).size.height,
                  child: InkWell(
                    onTap: () {
                      if (Provider.of<AppSetting>(context, listen: false)
                              .novelReadDirection ==
                          1) {
                        previousPage();
                      } else {
                        nextPage();
                      }
                    },
                    child: Container(),
                  ),
                ),

          Positioned(
            bottom: 8,
            right: 12,
            child: Text(
              Provider.of<AppSetting>(context).novelReadDirection == 2
                  ? ""
                  : "$_indexPage/${_pageContents.length} $_batteryStr电量 $_timeStr",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          //加载
          Positioned(
            top: 80,
            width: MediaQuery.of(context).size.width,
            child: _loading
                ? Container(
                    width: double.infinity,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  )
                : Container(),
          ),

          //顶部
          AnimatedPositioned(
            duration: Duration(milliseconds: 200),
            width: MediaQuery.of(context).size.width,
            child: Container(
              padding: EdgeInsets.only(
                  top: Provider.of<AppSetting>(context).comicReadShowStatusBar
                      ? 0
                      : MediaQuery.of(context).padding.top),
              width: MediaQuery.of(context).size.width,
              child: Material(
                  color: Color.fromARGB(255, 34, 34, 34),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      widget.novelTitle,
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      _currentItem.volume_name.trim() +
                          " · " +
                          _currentItem.chapter_name.trim(),
                      style: TextStyle(color: Colors.white),
                    ),
                    leading: BackButton(
                      color: Colors.white,
                    ),
                    trailing: IconButton(
                        icon: Icon(
                          Icons.share,
                          color: Colors.white,
                        ),
                        onPressed: () {}),
                  )),
            ),
            top: _showControls ? 0 : -100,
            left: 0,
          ),
          //底部
          AnimatedPositioned(
            duration: Duration(milliseconds: 200),
            width: MediaQuery.of(context).size.width,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              width: MediaQuery.of(context).size.width,
              color: Color.fromARGB(255, 34, 34, 34),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      ButtonTheme(
                        minWidth: 10,
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: FlatButton(
                          onPressed: previousChapter,
                          child: Text(
                            "上一话",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      Expanded(
                        child: !_loading
                            ? Provider.of<AppSetting>(context)
                                        .novelReadDirection ==
                                    2
                                ? Slider(
                                    value: _verSliderValue,
                                    max: _verSliderMax,
                                    onChanged: (e) {
                                      _controllerVer.jumpTo(e);
                                    },
                                  )
                                : Slider(
                                    value: _indexPage >= 1
                                        ? _indexPage - 1.toDouble()
                                        : 0,
                                    max: _pageContents.length - 1.toDouble(),
                                    onChanged: (e) {
                                      setState(() {
                                        _indexPage = e.toInt() + 1;
                                        _controller.jumpToPage(e.toInt() + 1);
                                      });
                                    },
                                  )
                            : Text(
                                "加载中",
                                style: TextStyle(color: Colors.white),
                              ),
                      ),
                      ButtonTheme(
                        minWidth: 10,
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                        child: FlatButton(
                          onPressed: nextChapter,
                          child: Text(
                            "下一话",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      )
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      Provider.of<AppUserInfo>(context).isLogin &&
                              widget.subscribe
                          ? createButton(
                              "已订阅",
                              Icons.favorite,
                              onTap: () async {
                                if (await UserHelper.novelSubscribe(
                                    widget.novelId,
                                    cancel: true)) {
                                  setState(() {
                                    widget.subscribe = false;
                                  });
                                }
                              },
                            )
                          : createButton(
                              "订阅",
                              Icons.favorite_border,
                              onTap: () async {
                                if (await UserHelper.novelSubscribe(
                                    widget.novelId)) {
                                  setState(() {
                                    widget.subscribe = true;
                                  });
                                }
                              },
                            ),
                      createButton("设置", Icons.settings, onTap: openSetting),
                      createButton("章节", Icons.format_list_bulleted, onTap: () {
                        setState(() {
                          _showChapters = true;
                        });
                      }),
                    ],
                  ),
                  SizedBox(height: 36)
                ],
              ),
            ),
            bottom: _showControls ? 0 : -180,
            left: 0,
          ),

          //右侧章节选择
          AnimatedPositioned(
            duration: Duration(milliseconds: 200),
            width: 200,
            child: Container(
                height: MediaQuery.of(context).size.height,
                color: Color.fromARGB(255, 24, 24, 24),
                padding: EdgeInsets.only(
                    top: Provider.of<AppSetting>(context).comicReadShowStatusBar
                        ? 0
                        : MediaQuery.of(context).padding.top),
                width: MediaQuery.of(context).size.width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          "目录(${widget.chapters.length})",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        )),
                    Expanded(
                      child: ListView(
                        children: widget.chapters
                            .map((f) => ListTile(
                                  dense: true,
                                  onTap: () async {
                                    if (f != _currentItem) {
                                      setState(() {
                                        _currentItem = f;
                                        _showChapters = false;
                                        _showControls = false;
                                      });

                                      await loadData();
                                    }
                                  },
                                  title: Text(
                                    f.chapter_name,
                                    style: TextStyle(
                                        color: f == _currentItem
                                            ? Theme.of(context)
                                                .colorScheme
                                                .secondary
                                            : Colors.white),
                                  ),
                                  subtitle: Text(
                                    f.volume_name,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ],
                )),
            top: 0,
            right: _showChapters ? 0 : -200,
          ),
        ],
      ),
    );
  }

  Duration pageChangeDura = Duration(milliseconds: 400);
  Curve curveWay = Curves.decelerate;

  void nextPage() {
    if (_controller.page > _pageContents.length) {
      nextChapter();
    } else {
      setState(() {
        var pageTo = _indexPage + 1;
        _controller.animateToPage(pageTo,
            duration: pageChangeDura, curve: curveWay);
        // ConfigHelper.setCurrentPage(
        //     widget.novelId, _currentItem.chapter_id, pageTo);
        NovelHistoryProvider.updateOrCreate(
            NovelHistory(widget.novelId, _currentItem.chapter_id, 1, 1));
      });
    }
  }

  void previousPage() {
    if (_controller.page == 1) {
      previousChapter();
      _indexPage = 1;
      // ConfigHelper.setCurrentPage(widget.novelId, _currentItem.chapter_id, 1);
      NovelHistoryProvider.updateOrCreate(NovelHistory(
          widget.novelId, _currentItem.chapter_id, _indexPage.toDouble(), 1));
    } else {
      setState(() {
        var pageTo = _indexPage - 1;
        _controller.animateToPage(pageTo,
            duration: pageChangeDura, curve: curveWay);
        NovelHistoryProvider.updateOrCreate(NovelHistory(
            widget.novelId, _currentItem.chapter_id, _indexPage.toDouble(), 1));
        // ConfigHelper.setCurrentPage(
        //     widget.novelId, _currentItem.chapter_id, pageTo);
      });
    }
  }

  Widget createButton(String text, IconData icon, {Function onTap}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: Column(
              children: <Widget>[
                Icon(icon, color: Colors.white),
                SizedBox(
                  height: 4,
                ),
                Text(
                  text,
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 打开设置弹窗
  void openSetting() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          color: Color.fromARGB(255, 34, 34, 34),
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 80,
                    child: Text(
                      "字号",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: createOutlineButton("小", onPressed: () async {
                      var size = Provider.of<AppSetting>(context, listen: false)
                          .novelFontSize;
                      if (size == 10) {
                        Fluttertoast.showToast(msg: '不能再小了');
                        return;
                      }
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelFontSize(size - 1);
                      await handelContent();
                    }),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                  Expanded(
                    child: createOutlineButton("大", onPressed: () async {
                      var size = Provider.of<AppSetting>(context, listen: false)
                          .novelFontSize;
                      if (size == 30) {
                        Fluttertoast.showToast(msg: '不能再大了');
                        return;
                      }
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelFontSize(size + 1);
                      await handelContent();
                    }),
                  )
                ],
              ),
              Row(
                children: <Widget>[
                  Container(
                    width: 80,
                    child: Text(
                      "行距",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: createOutlineButton("减少", onPressed: () async {
                      var height =
                          Provider.of<AppSetting>(context, listen: false)
                              .novelLineHeight;
                      if (height == 0.8) {
                        Fluttertoast.showToast(msg: '不能再减少了');
                        return;
                      }
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelLineHeight(height - 0.1);
                      await handelContent();
                    }),
                  ),
                  SizedBox(
                    width: 24,
                  ),
                  Expanded(
                    child: createOutlineButton("增加", onPressed: () async {
                      var height =
                          Provider.of<AppSetting>(context, listen: false)
                              .novelLineHeight;
                      if (height == 2.0) {
                        Fluttertoast.showToast(msg: '不能再增加了');
                        return;
                      }
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelLineHeight(height + 0.1);
                      await handelContent();
                    }),
                  )
                ],
              ),
              Row(
                children: <Widget>[
                  Container(
                    width: 80,
                    child: Text(
                      "方向",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: createOutlineButton("左右",
                        borderColor: Provider.of<AppSetting>(context)
                                    .novelReadDirection ==
                                0
                            ? Colors.blue
                            : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadDirection(0);
                    }),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: createOutlineButton("右左",
                        borderColor: Provider.of<AppSetting>(context)
                                    .novelReadDirection ==
                                1
                            ? Colors.blue
                            : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadDirection(1);
                    }),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: createOutlineButton("上下",
                        borderColor: Provider.of<AppSetting>(context)
                                    .novelReadDirection ==
                                2
                            ? Colors.blue
                            : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadDirection(2);
                    }),
                  )
                ],
              ),
              SizedBox(
                height: 8,
              ),
              Row(
                children: <Widget>[
                  Container(
                    width: 80,
                    child: Text(
                      "主题",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  Expanded(
                    child: createOutlineButtonColor(AppSetting.bgColors[0],
                        borderColor:
                            Provider.of<AppSetting>(context).novelReadTheme == 0
                                ? Colors.blue
                                : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadTheme(0);
                    }),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: createOutlineButtonColor(AppSetting.bgColors[1],
                        borderColor:
                            Provider.of<AppSetting>(context).novelReadTheme == 1
                                ? Colors.blue
                                : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadTheme(1);
                    }),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: createOutlineButtonColor(AppSetting.bgColors[2],
                        borderColor:
                            Provider.of<AppSetting>(context).novelReadTheme == 2
                                ? Colors.blue
                                : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadTheme(2);
                    }),
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: createOutlineButtonColor(AppSetting.bgColors[3],
                        borderColor:
                            Provider.of<AppSetting>(context).novelReadTheme == 3
                                ? Colors.blue
                                : null, onPressed: () {
                      Provider.of<AppSetting>(context, listen: false)
                          .changeNovelReadTheme(3);
                    }),
                  )
                ],
              )
            ],
          ),
        );
      },
    );
  }

  Widget createOutlineButton(String text,
      {Function onPressed, Color borderColor}) {
    if (borderColor == null) {
      borderColor = Colors.grey.withOpacity(0.6);
    }
    return OutlineButton(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      textColor: Theme.of(context).colorScheme.secondary,
      borderSide: BorderSide(color: borderColor),
      child: Text(
        text,
        style: TextStyle(color: Colors.white),
      ),
      onPressed: onPressed,
    );
  }

  Widget createOutlineButtonColor(Color color,
      {Function onPressed, Color borderColor}) {
    if (borderColor == null) {
      borderColor = Colors.grey.withOpacity(0.6);
    }
    return InkWell(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderColor),
          color: color,
        ),
        height: 32,
      ),
      onTap: onPressed,
    );
  }

  bool _loading = false;
  DefaultCacheManager _cacheManager = DefaultCacheManager();
  // 加载数据
  Future loadData({bool toEnd = false, bool toStart = false}) async {
    try {
      if (_loading) {
        return;
      }
      setState(() {
        _loading = true;

        _pageContents = ["加载中"];
        try {
          _controller.jumpToPage(1);
        } catch (e) {}
      });

      //检查缓存
      var url = NovelApi.instance.getNovelContentUrl(
          widget.novelId, _currentItem.volume_id, _currentItem.chapter_id);
      // print("url:" + url);
      var file = await _cacheManager.getFileFromCache(url);
      if (file == null) {
        file = await _cacheManager.downloadFile(url);
      }

      //var response = await http.get(url);
      var bodyBytes = await file.file.readAsBytes();
      if (String.fromCharCodes(bodyBytes.take(200))
          .contains(RegExp('<img.*?'))) {
        // print("image");
        var str = Utf8Decoder().convert(bodyBytes);
        List<String> imgs = [];
        for (var item
            in RegExp(r'<img.*?src=[' '""](.*?)[' '""].*?>').allMatches(str)) {
          // print(item.group(1));
          imgs.add(item.group(1));
        }
        _contents = Uint8List(0);
        setState(() {
          _isPicture = true;
          _pageContents = imgs;
        });
      } else {
        // var str = String.fromCharCodes(bodyBytes.take(200));
        // print("text:$str");
        setState(() {
          _isPicture = false;
        });
        _contents = bodyBytes;

        await handelContent();
      }

      // 跳转到尾页
      if (toEnd) {
        print("toEnd");
        var toPage = _pageContents.length;
        _controller.jumpToPage(toPage);
        _indexPage = toPage; // 未知原因导致跳页后onPageChanged返回index一直是2
        NovelHistoryProvider.updateOrCreate(NovelHistory(
            widget.novelId, _currentItem.chapter_id, toPage.toDouble(), 1));
      } else if (!toStart) {
        // 跳转到上次阅读页面
        var novelItem = await NovelHistoryProvider.getItem(widget.novelId);
        if (novelItem.chapterId == _currentItem.chapter_id) {
          var oldPage = (novelItem.page).floor();
          // ConfigHelper.getCurrentPage(widget.novelId, _currentItem.chapter_id);
          _controller.jumpToPage(oldPage);
          _indexPage = oldPage;
          // print("oldPage:$oldPage");
          // print("indexPage:$_indexPage");
        }
      }

      ConfigHelper.setNovelHistory(widget.novelId, _currentItem.chapter_id);
      UserHelper.comicAddNovelHistory(
          widget.novelId, _currentItem.volume_id, _currentItem.chapter_id);
    } catch (e) {
      print("novel_reader Exception:");
      print(e);
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future handelContent() async {
    if (_isPicture) {
      return;
    }
    var i = DateTime.now().millisecondsSinceEpoch;
    var width = window.physicalSize.width / window.devicePixelRatio;

    var height = window.physicalSize.height / window.devicePixelRatio;
    var par = ComputeParameter(_contents, width, height,
        ConfigHelper.getNovelFontSize(), ConfigHelper.getNovelLineHeight());
    var ls = await compute(computeContent, par);

    setState(() {
      _pageContents = ls;
      _fontSize = ConfigHelper.getNovelFontSize();
      _lineHeight = ConfigHelper.getNovelLineHeight();
    });
    print("加载用时(微秒):" + (DateTime.now().millisecondsSinceEpoch - i).toString());
  }

  static List<String> computeContent(ComputeParameter par) {
    var width = par.width;

    var height = par.height;
    var _content = HtmlUnescape()
        .convert(Utf8Decoder()
            .convert(par.content)
            .replaceAll('\r\n', '\n')
            .replaceAll("<br/>", "\n")
            .replaceAll('<br />', "\n")
            .replaceAll('\n\n\n', "\n")
            .replaceAll('\n', "\n  "))
        .replaceAll("\n  \n", "\n");
    var content = toSBC(_content);

    //计算每行字数
    var maxNum = (width - 12 * 2) / par.fontSize;
    var maxNumInt = maxNum.toInt();

    //对每行字数进行添加换行符
    var result = '';
    for (var item in content.split('\n')) {
      for (var i = 0; i < item.length; i++) {
        if ((i + 1) % maxNumInt == 0 && i != item.length - 1) {
          result += item[i] + "\n";
        } else {
          result += item[i];
        }
      }
      result += '\n';
    }
    //result = result.replaceAll('\n\n' , '\n');
    //计算每页行数
    double pageLineNumDouble =
        (height - (12 * 4)) / (par.fontSize * par.lineHeight);
    //int pageLineNum=  ((height - 12 * 2) %(_fontSize * _lineHeight)==0)? pageLineNum_double.truncate():pageLineNum_double.truncate()-1;
    int pageLineNum = pageLineNumDouble.floor();
    print(pageLineNumDouble);
    print(pageLineNum);
    //计算页数
    var lines = result.split("\n");
    var maxPages = (lines.length / pageLineNum).ceil();
    //处理出每页显示的文本
    List<String> ls = [];
    for (var i = 0; i < maxPages; i++) {
      var re = "";
      for (var item in lines.skip(i * pageLineNum).take(pageLineNum)) {
        re += item + "\n";
      }
      ls.add(re);
    }
    return ls;
  }

  // 半角转全角：
  static String toSBC(String input) {
    List<int> value = [];
    var array = input.codeUnits;
    for (int i = 0; i < array.length; i++) {
      if (array[i] == 32) {
        value.add(12288);
      } else if (array[i] > 32 && array[i] <= 126) {
        value.add((array[i] + 65248));
        //value.add(array[i]);
      } else {
        value.add(array[i]);
      }
    }
    return String.fromCharCodes(value);
  }

  void nextChapter() async {
    if (widget.chapters.indexOf(_currentItem) == widget.chapters.length - 1) {
      Fluttertoast.showToast(msg: '已经是最后一章了');
      return;
    }

    // ConfigHelper.setCurrentPage(widget.novelId, _currentItem.chapter_id, 1);
    _indexPage = 1;
    NovelHistoryProvider.updateOrCreate(
        NovelHistory(widget.novelId, _currentItem.chapter_id, 1, 1));

    setState(() {
      _currentItem = widget.chapters[widget.chapters.indexOf(_currentItem) + 1];
    });
    await loadData(toStart: true);
  }

  void previousChapter() async {
    if (widget.chapters.indexOf(_currentItem) == 0) {
      Fluttertoast.showToast(msg: '已经是最前面一章了');
      return;
    }

    // ConfigHelper.setCurrentPage(widget.novelId, _currentItem.chapter_id, 1);
    _indexPage = 1;
    NovelHistoryProvider.updateOrCreate(
        NovelHistory(widget.novelId, _currentItem.chapter_id, 1, 1));

    setState(() {
      _currentItem = widget.chapters[widget.chapters.indexOf(_currentItem) - 1];
    });
    await loadData(toEnd: true);
  }
}

class ComputeParameter {
  Uint8List content;
  double width;
  double height;
  double fontSize;
  double lineHeight;
  ComputeParameter(
      this.content, this.width, this.height, this.fontSize, this.lineHeight);
}
