// THESIS: Контур is a compact native control desk for choosing and running strategies.
// OWN-WORLD: chalk workspace, graphite navigation, forest-green action, Segoe UI.
// STORY: choose a profile, start its engine, inspect the actual process state.
// FIRST VIEWPORT: navigation left; status, profile picker and launch action right.
// FORM: native desktop utility; user-approved light/graphite/green direction.
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Drawing;
using System.Diagnostics;
using System.Collections.Generic;
using System.Windows.Forms;
using System.Xml.Serialization;
using System.Threading;
using System.Reflection;

[assembly: AssemblyTitle("Контур")]
[assembly: AssemblyProduct("Контур")]
[assembly: AssemblyVersion("1.0.1.0")]

namespace Kontur {
 public class Settings {
  public string Profile = "standard";
  public string GameMode = "Выключен";
  public string Tcp = "1024-65535", Udp = "1024-65535";
  public bool Tray = true, ConnectOnOpen = false;
 }
 public class Profile {
  public string Id, Name, Original;
  public override string ToString() { return Name; }
 }
 public static class Engine {
  public static List<Profile> Load(string root) {
   return File.ReadAllLines(Path.Combine(root,"profiles/catalog.txt"), Encoding.UTF8)
    .Where(x => !String.IsNullOrWhiteSpace(x)).Select(x => {
     string[] a=x.Split('|');
     if(a.Length!=3 || !System.Text.RegularExpressions.Regex.IsMatch(a[0], @"^[A-Za-z0-9-]+$")) throw new Exception("Повреждён каталог профилей.");
     return new Profile {Id=a[0],Name=a[1],Original=a[2]};
    }).ToList();
  }
  public static bool Ports(string value) {
   if(String.IsNullOrEmpty(value)) return false;
   foreach(string part in value.Split(',')) {
    if(!System.Text.RegularExpressions.Regex.IsMatch(part,@"^[1-9][0-9]{0,4}(-[1-9][0-9]{0,4})?$")) return false;
    string[] ends=part.Split('-'); int a=Int32.Parse(ends[0]), b=Int32.Parse(ends[ends.Length-1]);
    if(a>65535 || b>65535 || a>b) return false;
   }
   return true;
  }
  public static string Arguments(string root, Profile profile, Settings settings) {
   if(!Ports(settings.Tcp)||!Ports(settings.Udp)) throw new Exception("Порты: число 1–65535 или диапазон, через запятую.");
   string args=File.ReadAllText(Path.Combine(root,"profiles",profile.Id+".args"),Encoding.UTF8);
   args=args.Replace("{BIN}",Path.Combine(root,"bin")+Path.DirectorySeparatorChar)
    .Replace("{LISTS}",Path.Combine(root,"lists")+Path.DirectorySeparatorChar)
    .Replace("{GAME_TCP}",(settings.GameMode=="TCP"||settings.GameMode=="TCP и UDP")?settings.Tcp:"12")
    .Replace("{GAME_UDP}",(settings.GameMode=="UDP"||settings.GameMode=="TCP и UDP")?settings.Udp:"12");
   if(args.Contains("{")||args.Contains("%")) throw new Exception("Неизвестная переменная в профиле.");
   foreach(System.Text.RegularExpressions.Match m in System.Text.RegularExpressions.Regex.Matches(args,"=\"([^\"]+)\""))
    if(!File.Exists(m.Groups[1].Value)) throw new FileNotFoundException("Не найден файл профиля: "+m.Groups[1].Value);
   return args;
  }
 }
 public class MainForm : Form {
  readonly string root, data;
  Settings settings=new Settings();
  List<Profile> profiles;
  Process engine;
  readonly Panel work=new Panel();
  readonly List<Button> navigation=new List<Button>();
  ComboBox picker;
  Label state, detail;
  Button start, stop;
  TextBox journal;
  readonly StringBuilder log=new StringBuilder();
  NotifyIcon tray;
  readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
  readonly Color ink=Color.FromArgb(32,43,40), muted=Color.FromArgb(82,97,90), green=Color.FromArgb(33,100,73);
  bool busy;
  string currentPage="Подключение";
  public MainForm(string basePath) : this(basePath,false) {}
  public MainForm(string basePath,bool preview) {
   root=basePath; data=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Kontur");
   Directory.CreateDirectory(data);
   string settingsError=null;
   try { if(File.Exists(Path.Combine(data,"settings.xml"))) using(var f=File.OpenRead(Path.Combine(data,"settings.xml"))) settings=(Settings)new XmlSerializer(typeof(Settings)).Deserialize(f); }
   catch(Exception ex) { settingsError=ex.Message; }
   profiles=Engine.Load(root);
   if(profiles.Count==0) throw new Exception("Каталог профилей пуст.");
   foreach(string name in new[]{"list-general-user.txt","list-exclude-user.txt","ipset-exclude-user.txt"}) {
    string path=Path.Combine(root,"lists",name); if(!File.Exists(path)) File.WriteAllText(path,"",Encoding.UTF8);
   }
   Text="Контур"; StartPosition=FormStartPosition.CenterScreen; ClientSize=new Size(960,680); MinimumSize=new Size(900,660);
   BackColor=Color.FromArgb(244,246,242); ForeColor=ink; Font=new Font("Segoe UI",10); AutoScaleMode=AutoScaleMode.Dpi;
   string ico=Path.Combine(root,"launcher","kontur.ico"); if(File.Exists(ico)) Icon=new Icon(ico);
   var side=new Panel {Dock=DockStyle.Left,Width=210,BackColor=ink}; Controls.Add(side);
   var brand=new Label {Text="◉  Контур",ForeColor=Color.White,Font=new Font("Segoe UI",22,FontStyle.Bold),AutoSize=false,Location=new Point(22,28),Size=new Size(185,52)}; side.Controls.Add(brand);
   var sub=new Label {Text="Управление соединением",ForeColor=Color.FromArgb(193,210,200),Location=new Point(25,88),Size=new Size(175,48)}; side.Controls.Add(sub);
   int y=163;
   foreach(string name in new[]{"Подключение","Настройки","Домены","Инструменты","Журнал","О программе"}) {
    var b=new Button {Text=name,Tag=name,Location=new Point(14,y),Size=new Size(182,46),FlatStyle=FlatStyle.Flat,TextAlign=ContentAlignment.MiddleLeft,Padding=new Padding(14,0,0,0),ForeColor=Color.White,BackColor=ink,Cursor=Cursors.Hand};
    b.FlatAppearance.BorderSize=0; b.Click+=(s,e)=>Navigate((string)((Button)s).Tag); side.Controls.Add(b); navigation.Add(b); y+=53;
   }
   var foot=new Label {Text="Версия 1.0.1\nWindows · x64",Location=new Point(25,590),Size=new Size(160,55),ForeColor=Color.FromArgb(193,210,200),Anchor=AnchorStyles.Bottom|AnchorStyles.Left}; side.Controls.Add(foot);
   work.Dock=DockStyle.Fill; work.Padding=new Padding(34); work.AutoScroll=true; Controls.Add(work); work.BringToFront();
   tray=new NotifyIcon {Icon=Icon,Text="Контур — остановлен",Visible=false};
   var menu=new ContextMenuStrip(); menu.Items.Add("Открыть Контур",null,(s,e)=>Restore()); menu.Items.Add("Остановить",null,(s,e)=>StopEngine()); menu.Items.Add("Выход",null,(s,e)=>Close()); tray.ContextMenuStrip=menu; tray.DoubleClick+=(s,e)=>Restore();
   Resize+=(s,e)=>{if(WindowState==FormWindowState.Minimized && settings.Tray) {tray.Visible=true;Hide();}};
   FormClosing+=(s,e)=>{ if(busy) {e.Cancel=true;MessageBox.Show(this,"Дождитесь завершения операции во вкладке «Инструменты».","Контур");return;} StopEngine(); tray.Dispose(); timer.Stop(); };
   timer.Interval=500; timer.Tick+=(s,e)=>RefreshState(); timer.Start();
   Navigate("Подключение"); AddLog("Контур готов. Профилей: "+profiles.Count+". Статус показывает работу процесса, а не доступность сайтов.");
   if(settingsError!=null) AddLog("Настройки восстановлены по умолчанию: "+settingsError);
   Shown+=(s,e)=>{if(!preview&&settings.ConnectOnOpen) Safe(StartEngine);};
  }
  void Restore() {Show(); WindowState=FormWindowState.Normal; Activate(); tray.Visible=false;}
  Label Label(string text,int x,int y,int w,int h,int size,bool bold) {
   var l=new Label {Text=text,Location=new Point(x,y),Size=new Size(w,h),Font=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),ForeColor=ink}; work.Controls.Add(l);return l;
  }
  Button Button(string text,int x,int y,int w,Action action,bool primary) {
   var b=new Button {Text=text,Location=new Point(x,y),Size=new Size(w,43),FlatStyle=FlatStyle.Flat,BackColor=primary?green:Color.White,ForeColor=primary?Color.White:ink,Cursor=Cursors.Hand};
   b.FlatAppearance.BorderColor=Color.FromArgb(185,199,188); b.FlatAppearance.BorderSize=primary?0:1;
   b.Click+=(s,e)=>Safe(action); work.Controls.Add(b);return b;
  }
  void Safe(Action action) {try {action();} catch(Exception ex) {AddLog("Ошибка: "+ex.Message);MessageBox.Show(this,ex.Message,"Контур — действие не выполнено",MessageBoxButtons.OK,MessageBoxIcon.Warning);}}
  void Heading(string name,string sub) {Label(name,34,28,650,48,24,true);Label(sub,36,88,645,54,10,false).ForeColor=muted;}
  void Navigate(string page) {
   currentPage=page; work.Controls.Clear(); picker=null;state=null;detail=null;start=null;stop=null;journal=null;
   foreach(var b in navigation) b.BackColor=(string)b.Tag==page?green:ink;
   if(page=="Подключение") Connection(); else if(page=="Настройки") Preferences(); else if(page=="Домены") Domains(); else if(page=="Инструменты") Tools(); else if(page=="Журнал") Journal(); else About();
  }
  Profile Selected() {return profiles.FirstOrDefault(x=>x.Id==settings.Profile)??profiles[0];}
  void Connection() {
   Heading("Ваш маршрут в сеть","Выберите стратегию и запустите обработку трафика.");
   state=Label("●  Остановлен",36,166,630,45,19,true);
   detail=Label("",36,218,630,54,10,false); detail.ForeColor=muted;
   Label("Профиль соединения",36,300,500,28,12,true);
   picker=new ComboBox {Location=new Point(36,339),Size=new Size(610,32),DropDownStyle=ComboBoxStyle.DropDownList,Font=new Font("Segoe UI",12)};
   picker.Items.AddRange(profiles.ToArray()); picker.SelectedItem=Selected(); picker.SelectedIndexChanged+=(s,e)=>Safe(()=>{settings.Profile=((Profile)picker.SelectedItem).Id;Save();}); work.Controls.Add(picker);
   Label("Начните с основного. Если сайты не открываются, остановите\nсоединение и попробуйте один из ALT-профилей.",36,394,630,60,11,false).ForeColor=muted;
   start=Button("Запустить",36,487,295,StartEngine,true); stop=Button("Остановить",347,487,299,StopEngine,false);
   Label("Профиль применяется при следующем запуске.\nЗакрытие приложения останавливает его сетевой процесс.",36,558,630,56,10,false).ForeColor=muted;
   RefreshState();
  }
  bool Running() {return engine!=null&&!engine.HasExited;}
  void StartEngine() {
   if(Running()) return;
   if(Process.GetProcessesByName("winws").Length>0) throw new Exception("Уже работает другой winws. Остановите старый BAT или службу через прежнее меню, затем повторите запуск.");
   string exe=Path.Combine(root,"bin","winws.exe"); if(!File.Exists(exe)) throw new FileNotFoundException("Не найден bin/winws.exe. Распакуйте весь архив.");
   Profile p=Selected(); string args=Engine.Arguments(root,p,settings);
   var info=new ProcessStartInfo(exe,args) {WorkingDirectory=Path.Combine(root,"bin"),UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   if(engine!=null) {engine.Dispose();engine=null;}
   var pending=new Process {StartInfo=info}; pending.OutputDataReceived+=(s,e)=>{if(e.Data!=null) QueueLog(e.Data);}; pending.ErrorDataReceived+=(s,e)=>{if(e.Data!=null) QueueLog(e.Data);};
   try {if(!pending.Start()) throw new Exception("Windows не запустила движок.");engine=pending;}
   catch {pending.Dispose();throw;}
   engine.BeginOutputReadLine(); engine.BeginErrorReadLine(); AddLog("Запрошен запуск профиля "+p.Name+". PID "+engine.Id); RefreshState();
  }
  void StopEngine() {
   if(engine==null) return;
   try {if(!engine.HasExited) {engine.Kill();engine.WaitForExit(3000);} AddLog("Сетевой процесс остановлен.");engine.Dispose();engine=null;}
   catch(Exception ex) {AddLog("Не удалось остановить процесс: "+ex.Message);}
   RefreshState();
  }
  void RefreshState() {
   bool active=Running();
   if(engine!=null&&!active) {AddLog("Процесс завершился. Код: "+engine.ExitCode+". Если запуск не удался, проверьте журнал и другой профиль."); engine.Dispose();engine=null;}
   tray.Text=active?"Контур — процесс работает":"Контур — остановлен";
   if(state!=null) {state.Text=active?"●  Процесс работает":"●  Остановлен";state.ForeColor=active?green:ink;detail.Text=active?"Обработка трафика активна. Проверяйте доступность сайтов в браузере.":"Запустите профиль, чтобы начать обработку трафика."; start.Enabled=!active;stop.Enabled=active;picker.Enabled=!active;}
  }
  void Save() {
   string target=Path.Combine(data,"settings.xml"), tmp=target+".tmp";
   using(var f=File.Create(tmp)) new XmlSerializer(typeof(Settings)).Serialize(f,settings);
   if(File.Exists(target)) File.Replace(tmp,target,null); else File.Move(tmp,target);
  }
  void Preferences() {
   Heading("Настройки","Изменения сетевых параметров вступят в силу после перезапуска профиля.");
   Label("Игровой трафик",36,157,600,30,14,true);
   var mode=new ComboBox {Location=new Point(36,198),Width=610,DropDownStyle=ComboBoxStyle.DropDownList}; mode.Items.AddRange(new object[]{"Выключен","TCP","UDP","TCP и UDP"});mode.SelectedItem=settings.GameMode;if(mode.SelectedIndex<0) mode.SelectedIndex=0;work.Controls.Add(mode);
   Label("TCP-порты",36,245,285,25,10,false); Label("UDP-порты",352,245,290,25,10,false);
   var tcp=new TextBox {Location=new Point(36,276),Width=294,Text=settings.Tcp};var udp=new TextBox {Location=new Point(352,276),Width=294,Text=settings.Udp};work.Controls.Add(tcp);work.Controls.Add(udp);
   Label("Например: 27015,27036-27037. Допустимы порты 1–65535.",36,317,620,35,10,false).ForeColor=muted;
   Label("Поведение приложения",36,380,610,30,14,true);
   var min=new CheckBox {Text="Сворачивать в трей при минимизации",Checked=settings.Tray,Location=new Point(36,425),Size=new Size(610,30)};
   var auto=new CheckBox {Text="Запускать выбранный профиль при открытии Контура",Checked=settings.ConnectOnOpen,Location=new Point(36,465),Size=new Size(610,35)};work.Controls.Add(min);work.Controls.Add(auto);
   Button("Сохранить настройки",36,536,295,()=>{if(!Engine.Ports(tcp.Text)||!Engine.Ports(udp.Text)) throw new Exception("Проверьте порты: например 27015,27036-27037."); settings.GameMode=(string)mode.SelectedItem;settings.Tcp=tcp.Text;settings.Udp=udp.Text;settings.Tray=min.Checked;settings.ConnectOnOpen=auto.Checked;Save();AddLog("Настройки сохранены.");MessageBox.Show(this,"Настройки сохранены. Для сетевых изменений перезапустите профиль.","Контур");},true);
  }
  void Domains() {
   Heading("Свои домены","Один домен на строку, без https:// и путей. Комментарии начинаются с #.");
   var kind=new ComboBox {Location=new Point(36,158),Width=610,DropDownStyle=ComboBoxStyle.DropDownList};kind.Items.AddRange(new object[]{"Добавить в обработку","Исключить из обработки"}); work.Controls.Add(kind);
   var editor=new TextBox {Multiline=true,ScrollBars=ScrollBars.Vertical,AcceptsReturn=true,Location=new Point(36,211),Size=new Size(610,299),Font=new Font("Consolas",11)};work.Controls.Add(editor);
   Func<string> file=()=>Path.Combine(root,"lists",kind.SelectedIndex==0?"list-general-user.txt":"list-exclude-user.txt");
   kind.SelectedIndexChanged+=(s,e)=>Safe(()=>editor.Text=File.ReadAllText(file(),Encoding.UTF8));kind.SelectedIndex=0;
   Button("Сохранить список",36,536,295,()=>{foreach(string line in editor.Lines) {string v=line.Trim();if(v.Length==0||v.StartsWith("#")) continue;if(Uri.CheckHostName(v)!=UriHostNameType.Dns || !v.Contains(".")) throw new Exception("Некорректный домен: "+v);} File.WriteAllText(file(),editor.Text, new UTF8Encoding(false));AddLog("Список доменов сохранён.");MessageBox.Show(this,"Список сохранён. Перезапустите профиль.","Контур");},true);
   Label("Переключение списка заменит несохранённый текст.",36,593,640,30,10,false).ForeColor=muted;
  }
  void Tools() {
   Heading("Инструменты","Дополнительные возможности исходной сборки. Результаты — в журнале.");
   Label("AI Unlock",36,155,610,30,15,true);
   Label("Включение изменяет системный hosts. Отключение удаляет\nзаписи AI Unlock; резервные копии сохраняются в utils.",36,197,630,55,10,false).ForeColor=muted;
   Button("Включить AI Unlock",36,266,294,()=>Script("ai-unlock.ps1","Enable"),true);
   Button("Отключить AI Unlock",352,266,294,()=>Script("ai-unlock.ps1","Disable"),false);
   Button("Обновить адреса AI",36,323,294,()=>Script("ai-unlock.ps1","Update"),false);
   Label("Telegram Desktop",36,405,610,30,15,true);
   Label("Локальный прокси использует отдельное окно и системный трей.\nНастройки подключения подтверждаются в Telegram.",36,447,630,53,10,false).ForeColor=muted;
   Button("Запустить прокси",36,519,294,()=>Script("telegram-proxy.ps1","Start"),true);
   Button("Подключить Telegram",352,519,294,()=>Script("telegram-proxy.ps1","Connect"),false);
   Button("Остановить прокси",36,576,294,()=>Script("telegram-proxy.ps1","Stop"),false);
  }
  async void Script(string file,string mode) {
   if(busy) {MessageBox.Show(this,"Другая операция ещё выполняется. Откройте журнал.","Контур");return;}
   busy=true; AddLog("Выполняется: "+file+" / "+mode);
   try {
    string path=Path.Combine(root,"utils",file); if(!File.Exists(path)) throw new FileNotFoundException("Не найден инструмент: "+path);
    var info=new ProcessStartInfo("powershell.exe","-NoProfile -ExecutionPolicy Bypass -File \""+path+"\" -Mode "+mode) {UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=root};
    using(var process=new Process {StartInfo=info}) {
     process.OutputDataReceived+=(s,e)=>{if(e.Data!=null) QueueLog(e.Data);};process.ErrorDataReceived+=(s,e)=>{if(e.Data!=null) QueueLog(e.Data);};
     process.Start();process.BeginOutputReadLine();process.BeginErrorReadLine();await System.Threading.Tasks.Task.Run(()=>process.WaitForExit());
     AddLog("Операция завершена. Код: "+process.ExitCode);if(process.ExitCode!=0) MessageBox.Show(this,"Операция завершилась с ошибкой. Подробности в журнале.","Контур");
    }
   } catch(Exception ex) {AddLog("Ошибка: "+ex.Message);MessageBox.Show(this,ex.Message,"Контур");} finally {busy=false;}
  }
  void Journal() {
   Heading("Журнал","Вывод сетевого процесса и результаты действий. Последние 60 000 символов.");
   journal=new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,WordWrap=false,Location=new Point(36,155),Size=new Size(610,368),Font=new Font("Consolas",10),Text=log.ToString(),BackColor=Color.White};work.Controls.Add(journal);
   Button("Открыть папку журналов",36,548,295,()=>Process.Start("explorer.exe",data),false);
  }
  void QueueLog(string value) {if(!IsDisposed&&IsHandleCreated) try {BeginInvoke((Action)(()=>AddLog(value)));} catch(InvalidOperationException) {}}
  void AddLog(string value) {
   string line=DateTime.Now.ToString("HH:mm:ss")+"  "+value+Environment.NewLine; log.Append(line);if(log.Length>60000)log.Remove(0,log.Length-60000);
   try {string path=Path.Combine(data,"kontur.log");if(File.Exists(path)&&new FileInfo(path).Length>2000000)File.Move(path,Path.Combine(data,"kontur.previous.log")+"."+DateTime.Now.Ticks);File.AppendAllText(path,line,Encoding.UTF8);}catch(IOException){}catch(UnauthorizedAccessException){}
   if(journal!=null) {journal.Text=log.ToString();journal.SelectionStart=journal.TextLength;journal.ScrollToCaret();}
  }
  void About() {
   Heading("Контур","Версия 1.0.1 · независимая оболочка для Windows");
   Label("Один интерфейс. Разные маршруты.",36,164,630,80,21,true);
   Label("Выбор из 22 стратегий, настройки игровых портов, свои домены,\nAI Unlock и Telegram-прокси. Исходный код оболочки открыт.",36,270,630,70,11,false).ForeColor=muted;
   Label("Использует движок zapret (bol-van), стратегии Flowseal,\nWinDivert и TG WS Proxy. Название и интерфейс Контур —\nотдельная разработка. ПО предоставляется без гарантий.\nЛицензии компонентов находятся в папке licenses.",36,371,630,115,11,false).ForeColor=muted;
   Button("Репозиторий",36,525,294,()=>Process.Start("https://github.com/FirstRyzen/Zapret-AIUNLOCK-TelegramUnlock"),true);
   Button("Лицензии",352,525,294,()=>Process.Start("explorer.exe",Path.Combine(root,"licenses")),false);
  }
  public void CapturePage(string page,string path) {Navigate(page);PerformLayout();Refresh();using(var bmp=new Bitmap(Width,Height)) {DrawToBitmap(bmp,new Rectangle(0,0,Width,Height));bmp.Save(path);}}
 }
 public static class Program {
  [STAThread] public static void Main(string[] args) {
   bool owned; using(var mutex=new Mutex(true,"Local\\Kontur.Launcher",out owned)) {
    if(!owned) {MessageBox.Show("Контур уже открыт. Проверьте панель задач и системный трей.","Контур");return;}
    Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
    try {Application.Run(new MainForm(AppDomain.CurrentDomain.BaseDirectory));}
    catch(Exception ex) {MessageBox.Show(ex.Message+"\nРаспакуйте полный архив рядом с Kontur.exe.","Контур — ошибка запуска");}
   }
  }
 }
}
