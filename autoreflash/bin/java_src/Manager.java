import javax.swing.*;
import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.Arrays;
import java.text.SimpleDateFormat;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.awt.Color;
import java.io.File;
import java.awt.event.MouseListener;
import java.awt.event.MouseEvent;
import java.util.Hashtable;
import java.awt.Graphics;
import java.awt.GridLayout;
import java.util.Enumeration;
import java.io.BufferedReader;
import java.io.FileReader;
import java.io.FileNotFoundException;
import java.io.IOException;

public class Manager extends JApplet  implements ActionListener 
{

	private static class Clock implements ActionListener
	{
		public SimpleDateFormat sdf = new SimpleDateFormat("HH:mm");
		
		private static Manager parent;
		private static Timer timer;
		
		public Clock(Manager prnt, int intrvl, int delay)
		{
			parent = prnt;
			timer = new Timer(intrvl, this);
			timer.setInitialDelay(delay);
			parent.curTime.setText(sdf.format(Calendar.getInstance().getTime()));
			timer.start();
		}
		
		public void actionPerformed(ActionEvent e)
		{
		 	parent.updateClock(sdf.format(Calendar.getInstance().getTime()));
		}
	}
	
	private static class Alarm implements ActionListener
	{
		public SimpleDateFormat sdf = new SimpleDateFormat("HH:mm");
		
		private static Manager parent;
		private static Timer timer;
		private static int endHour, endMin;
		
		public Alarm(Manager prnt, int endHr, int endMn)
		{
			parent = prnt;
			endHour = endHr;
			endMin = endMn;
		}
		
		public void init(int delay)
		{
			timer = new Timer(60000, this);
			timer.setInitialDelay(delay);
			timer.start();
		}
		
		public void stop()
		{
			timer.stop();
		}
		
		public void actionPerformed(ActionEvent e)
		{
			String[] curTime = sdf.format(Calendar.getInstance().getTime()).toString().split(":");
			int curHour = Integer.parseInt(curTime[0]);

			if (endHour == curHour)
			{
				int curMin = Integer.parseInt(curTime[1]);
				if (endMin == curMin)
				{
					timer.stop();
					parent.timeExpired();
				}
			}
					
		}
	}
	
	private static class Starter implements Runnable
	{
		private static Manager parent;
		
		public Starter(Manager prnt)
		{
			parent = prnt;
		}
		
		public void run()
		{
			try {
				Enumeration en = parent.allProjects.keys();

				//Setup for each Project that is valid
				while(en.hasMoreElements())
				{
					String projName = (String)en.nextElement();
					Project projObj = null;
					projObj = allProjects.get(projName);
					
					if (projObj == null || !projObj.isValid())
						continue;
					
					if (!projObj.isRunning())
					{
						File dir = new File("../config_dir/" + projName);
				
						// I dont want to move any .fhx - lets assume I will only have one .fhx per project and warn otherwise.
						String[] files = dir.list();
						int fhx_cnt = 0;
						for (int i=0; i < files.length; i++) {
							if (files[i].endsWith(".fhx")) {
								fhx_cnt++;
								System.out.println("Notice: found fhx file: " + files[i]);
								/*String temp = files[i];
								temp = temp.replace("fhx", "old_fhx");
								File oldfile = new File(dir, files[i]);
								File newfile = new File(dir, temp);
								Boolean success = oldfile.renameTo(newfile);
								if (!success)
									System.out.println("Error renaming file!");
								*/
							}
						}
						if (fhx_cnt > 1)
							System.out.println("Warning: multiple .fhx files exists for "+projName+"!");
							
						projObj.start(parent.stopTime.getText());

						if (en.hasMoreElements()){
							System.out.println("Notice: sleeping 15 seconds before starting next project.");
							Thread.sleep(15000);
						}
					}
				}
			} catch (InterruptedException e) {
				System.out.println("Warning: Start All thread interrupted!");
			}
		
		}
		
	}

	public static final long serialVersionUID = 1;
	public static Hashtable<String,Project> allProjects = new Hashtable<String,Project>();
	

	public JLabel curTime;
	public JLabel stopTime;
	private static Clock clock;
	private static Alarm alarm;
	private static Thread starter;
	
	
    public void init() 
    {
		//Execute a job on the event-dispatching thread:
		//creating this applet's GUI.
        try {
            SwingUtilities.invokeAndWait(new Runnable() {
                public void run() {
                    createGUI();
                }
            });
        } catch (Exception e) {
			System.out.println("ERROR IN INIT:");
			e.printStackTrace();
        }
   }
   
   public boolean projRunning()
   {
   
	Enumeration en = allProjects.keys();

	//Setup for each Project that is valid
	while(en.hasMoreElements())
	{
		String projName = (String)en.nextElement();
		Project projObj = null;

		projObj = allProjects.get(projName);

		if(projObj == null || !projObj.isValid())
			continue;

		if(projObj.isRunning())
			return true;
	}
	
	return false;
   }
   
   public String getProjStopTimes()
   {
   	String projects = "";
	Enumeration en = allProjects.keys();

	//Setup for each Project that is valid
	while(en.hasMoreElements())
	{
		String projName = (String)en.nextElement();
		Project projObj = null;

		projObj = allProjects.get(projName);

		if(projObj == null || !projObj.isValid())
			continue;

		if(projObj.isRunning())
		{
			String temp = projObj.getStopTime();
			
			if (!temp.isEmpty())
				projects += projName + " (stops at " + temp  + ")\n";
		}
	}
	
	return projects;
   }
   
   public String getProjNoStopTimes()
   {
   	String projects = "";
	Enumeration en = allProjects.keys();

	//Setup for each Project that is valid
	while(en.hasMoreElements())
	{
		String projName = (String)en.nextElement();
		Project projObj = null;

		projObj = allProjects.get(projName);

		if(projObj == null || !projObj.isValid())
			continue;

		if(projObj.isRunning())
		{
			String temp = projObj.getStopTime();
			
			if (temp.isEmpty())
				projects += projName + " (no stop time set)\n";
		}
	}
	
	return projects;
   }
   
   public void updateClock(String newTime)
   {
	curTime.setText(newTime);
	prePaint();
   }
   
   public void timeExpired()
   {
   	JOptionPane pane = new JOptionPane("End of test time reached!\nProjects with set stop times will finish their current test iteration and exit.", JOptionPane.INFORMATION_MESSAGE);
	JDialog dialog = pane.createDialog("");
	dialog.setModal(false);
	dialog.setVisible(true);
	alarm = null;
	stopTime.setText("");
	prePaint();
   }
   
   
   public void setStopTime()
   {
   
 	String[] hours = { "00", "01", "02", "03", "04", "05", "06", "07", "08", "09", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20", "21", "22", "23" };
	String[] minutes = {"00","01","02","03","04","05","06","07","08","09","10","11","12","13","14","15","16","17","18","19",
			    "20","21","22","23","24","25","26","27","28","29","30","31","32","33","34","35","36","37","38","39",
			    "40","41","42","43","44","45","46","47","48","49","50","51","52","53","54","55","56","57","58","59"};
	Object[] options = { "Set Stop Time", "Clear Stop Time", "Cancel" };
 
 
 	JComboBox hourList = new JComboBox(hours);
	JComboBox minList = new JComboBox(minutes);
	Object[] hourObj = { "Select hour:", hourList };
	Object[] minObj = { "Select minute:", minList };
	Object[] test  = { hourObj, minObj };
 	int result = JOptionPane.showOptionDialog(null, test, "Autotest Stop Time", JOptionPane.YES_NO_CANCEL_OPTION, JOptionPane.QUESTION_MESSAGE, null, options, null);
	
	if (result == JOptionPane.YES_OPTION)
	{
		String h = (String)hourList.getSelectedItem();
		String m = (String)minList.getSelectedItem();
		int endHour = Integer.parseInt(h);
		int endMin = Integer.parseInt(m);
		alarm = new Alarm(this, endHour, endMin);
		long pause = 60000 - (System.currentTimeMillis() % 60000);
		alarm.init((int)pause);
		stopTime.setText(h + ":" + m);
		if (projRunning())
		{
			String projStopTimes = getProjStopTimes();
			String projNoStopTimes = getProjNoStopTimes();

			JOptionPane.showMessageDialog(null, "Projects are currently running!\nThe stop time can only be changed before the project has started.\n\nThe following projects will not be affected by this change:\n\n" + projStopTimes + projNoStopTimes);
			//JOptionPane pane = new JOptionPane("Projects are currently running with set stop times! A project must be killed to change its stop time.\n\n" + projEndTimes, JOptionPane.INFORMATION_MESSAGE);
			//JDialog dialog = pane.createDialog("");
			//dialog.setModal(false);
			//dialog.setVisible(true);
		}
		
	}
	else if (result == JOptionPane.NO_OPTION)
	{
		if (alarm != null)
		{
			stopTime.setText("");
			alarm.stop();
			alarm = null;
			if (projRunning())
			{
				String projStopTimes = getProjStopTimes();
				if (!projStopTimes.isEmpty())
				{
					JOptionPane.showMessageDialog(null, "Projects are currently running with set stop times!\nThe stop time can only be changed before the project has started.\n\nThe following projects will not be affected by this change:\n\n" + projStopTimes);
					//JOptionPane pane = new JOptionPane("Projects are currently running with set stop times! A project must be killed to change its stop time.\n\n" + projEndTimes, JOptionPane.INFORMATION_MESSAGE);
					//JDialog dialog = pane.createDialog("");
					//dialog.setModal(false);
					//dialog.setVisible(true);
				}
			}
		}
		else
		{
			JOptionPane.showMessageDialog(null, "No stop time is set!");
			return;
		}
	}
	else
		return;

   }

	public void createGUI()
	{
		//Giant JPanel to hold everything
		JPanel everything = new JPanel();
		everything.setLayout(new BoxLayout(everything,BoxLayout.Y_AXIS));

		Enumeration en = allProjects.keys();
		
		//Setup top row panel for times
		JPanel pTime = new JPanel();
		pTime.setLayout(new GridLayout(1,4));
		JLabel curLabel = new JLabel("Current Time:");
		pTime.add(curLabel);
		curTime = new JLabel("");
		pTime.add(curTime);
		JLabel stopLabel = new JLabel("Stop Time:");
		pTime.add(stopLabel);
		stopTime = new JLabel("");
		pTime.add(stopTime);
		everything.add(pTime);
		

		//Setup for each Project that is valid
		while(en.hasMoreElements())
		{
			String projName = (String)en.nextElement();
			Project projObj = null;

			projObj = allProjects.get(projName);

			if(projObj == null)
				continue;

			//Create a project Panel
			JPanel pCont = new JPanel();
			pCont.setLayout(new GridLayout(1,6));
			projObj.setPanel(pCont);

			//Add a name for the project
			JLabel name = new JLabel(projObj.getName());
			pCont.add(name);

			//Add all 3 buttons, start, pause, stop
			JButton startButton = new JButton("Start");
			pCont.add(startButton);
			projObj.setStartButton(startButton);
			startButton.setActionCommand(projObj.getName()+" start");
			startButton.addActionListener(this);

			JButton pauseButton= new JButton("Pause");
			pCont.add(pauseButton);
			projObj.setPauseButton(pauseButton);
			pauseButton.setActionCommand(projObj.getName()+" pause");
			pauseButton.addActionListener(this);

			JButton stopButton= new JButton("Stop");
			pCont.add(stopButton);
			projObj.setStopButton(stopButton);
			stopButton.setActionCommand(projObj.getName()+" stop");
			stopButton.addActionListener(this);

			JButton killButton= new JButton("Kill");
			pCont.add(killButton);
			projObj.setKillButton(killButton);
			killButton.setActionCommand(projObj.getName()+" kill");
			killButton.addActionListener(this);

			JButton kermitButton= new JButton("Kermit");
			pCont.add(kermitButton);
			projObj.setKermitButton(kermitButton);
			kermitButton.setActionCommand(projObj.getName()+" kermit");
			kermitButton.addActionListener(this);

			//Add container to everything container
			everything.add(pCont);
		}

		//Add the button panel
		//Create a project Panel 
		JPanel pStartStop = new JPanel();
		pStartStop.setLayout(new GridLayout(1,2));
		JButton startAllButton = new JButton("Start All");
		JButton killAllButton = new JButton("Kill All");
		pStartStop.add(startAllButton);
		pStartStop.add(killAllButton);
		startAllButton.setActionCommand("startAll");
		startAllButton.addActionListener(this);
		killAllButton.setActionCommand("killAll");
		killAllButton.addActionListener(this);
		everything.add(pStartStop);
		
		JPanel pCont = new JPanel();
		pCont.setLayout(new GridLayout(1,3));
		JButton closeButton = new JButton("Close");
		JButton refreshButton = new JButton("Refresh");
		JButton timerButton = new JButton("Set Stop Time");
		pCont.add(closeButton);
		pCont.add(refreshButton);
		pCont.add(timerButton);
		closeButton.setActionCommand("close");
		closeButton.addActionListener(this);
		refreshButton.setActionCommand("refresh");
		refreshButton.addActionListener(this);
		timerButton.setActionCommand("timer");
		timerButton.addActionListener(this);

		everything.add(pCont);

		add(everything);
		
		// Synchronize to system clock, then create clock timer
		long pause = 60000 - (System.currentTimeMillis() % 60000);
		clock = new Clock(this, 60000, (int)pause);
		
		starter = null;
		
		prePaint();
    }


	public void actionPerformed(ActionEvent e)
	{
	
		String action = e.getActionCommand();
		
		String[] words = action.split(" ");

		if(words.length == 2)
		{
			String project = words[0];
			String button = words[1];

			if(allProjects.containsKey(words[0]))
			{
				Project projObj = allProjects.get(words[0]);
				
				if(words[1].equals("stop"))
				{
					projObj.stop();
				}
				else if(words[1].equals("start"))
				{
					projObj.start(stopTime.getText());
				}
				else if(words[1].equals("pause"))
				{
					projObj.pause();
				}
				else if(words[1].equals("kill"))
				{
					projObj.kill();
				}
				else if(words[1].equals("kermit"))
				{
					projObj.kermit();
				}
			}
			else
			{
				System.err.println("Could not find project named:"+words[0]);
			}
		}
		else if(words.length == 1)
		{
			if(words[0].equals("close"))
			{
				System.exit(0);
			}
			else if(words[0].equals("refresh"))
			{
				//no-op
			}
			else if(words[0].equals("timer"))
			{
				setStopTime();
			}
			else if(words[0].equals("startAll"))
			{
				if (starter == null)
				{
					starter = new Thread(new Starter(this));
					starter.start();
				}
				else
				{
					if (!starter.isAlive())
					{
						starter = new Thread(new Starter(this));
						starter.start();
					}
				}
			}
			else if(words[0].equals("killAll"))
			{
				if (starter != null)
				{
					if (starter.isAlive())
					{
						starter.interrupt();
						starter = null;
					}
				}
				Project.killAll();
			}
		}
		
		prePaint();
	}

	public void start()
	{
	}

	public void destroy()
	{
		cleanUp();
	}

	public void cleanUp()
	{
      //Execute a job on the event-dispatching thread:
        //taking the text field out of this applet.
        try {
            SwingUtilities.invokeAndWait(new Runnable() {
                public void run() {
                }
            });
        } catch (Exception e) {
            System.err.println("cleanUp didn't successfully complete");
        }
    }

    public String readFile(File file)
	{
		FileReader fr = null;
		BufferedReader br = null;
		StringBuilder sb = new StringBuilder();

		if(file == null)
			return null;

    	try {
    		fr = new FileReader(file);
 			br = new BufferedReader(fr);
	        String line = br.readLine();

        	while (line != null) {
            	sb.append(line);
            	sb.append("\n");
            	line = br.readLine();
            }
		}catch (FileNotFoundException e){
			e.printStackTrace();
		}catch (IOException e){
			e.printStackTrace();
		}finally{
			// dispose all the resources after using them.
			if (br != null){
				try { br.close(); }
				catch(Exception e) { }
			}
			if (fr != null){
				try { fr.close(); }
				catch(Exception e) { }
			}
		}
		//Strip any leading or trailing whitespace
		return sb.toString().trim();
	}

    public static void main(String args[])
    {
    	String config_dir = "../nand_config_dir";
        Manager app = new Manager();

		JFrame.setDefaultLookAndFeelDecorated(true);
		JFrame test = new JFrame("Autotest Manager/Dashboard");

		//Find which projects we are going to monitor
		File configDir = new File(config_dir);
		if(configDir.isDirectory() && configDir.list().length > 0)
		{
			List<String> ls = Arrays.asList(configDir.list());
			File mappings = new File(configDir,"mappings.txt");
			if(!mappings.isFile()){
				System.out.println("Error: cannot find mappings.txt file!");
				System.exit(-1);
			}

			String text = app.readFile(mappings);
			if(text= null || text.length() < 1){
				System.out.println("Error: cannot read mappings.txt file!");
				System.exit(-1);
			}

			String[] lines = text.split("\n");
			for (int i=0; i<lines.length; i++)
			{
				String[] line = lines[i].split(" ");
				// Need: project_name serial_no serial1 [serial2 serial3 ...]
				int fidx = ls.indexOf(line[0]);
				if(line.length > 2 && fidx > -1)
				{
					File prodDir = new File(configDir, ls.get(fidx));
					if (prodDir.isDirectory()){
						// Create new project object (Project_Directory, Product_Name, Product_ID, Product_Serial_Number)
						try{
							Project project = new Project(prodDir, line[0], line[1], line[2]);
							for (int j=3; j<line.length; ++j){
								String[] tempTTY = line[j].split(":", 2);
								if (tempTTY.length > 1){
									project.addTTY(tempTTY[0], tempTTY[1]);
									if (tempTTY[0].equals("default"))
										project.setDefaultTTY(tempTTY[0]);
								}else
									System.out.println("Warning: malformed tty syntax of `"+line[j]+"` for device `"+line[1]+"`.\nSkipping.");
							}
							if (project.getTTYs().size() > 0){
								System.out.println("Test name is: "+project.getName());
								allProjects.put(project.getName(), project);
							}else
								System.out.println("Warning: Skipping test `"+project.getName()+"` - no TTY defined.");
						}catch(Exception e){
							System.out.println("Error: encountered exception creating Project object for `"+line[0]+"-"+line[2]+"`. Skipping project.");
						}
					}else
						System.out.println("Warning: cannot find directory for `"+line[0]+"`. Skipping project.");
				}else
					System.out.println("Warning: cannot find directory for `"+line[0]+"`. Skipping project.");
			}
		}else
			System.out.println("Warning: cannot configuration directory: `"+config_dir+"`!");

        app.init();
        app.start();
		test.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
		test.getContentPane().add("Center",app);
		//test.setSize(new Dimension(200,200));
		test.pack();
		test.setVisible(true);
    }

	// Mouse events
	public void mouseEntered(MouseEvent event) {}
	public void mouseExited(MouseEvent event) {}
	public void mousePressed(MouseEvent event) {}
	public void mouseReleased(MouseEvent event) {}

	public void mouseClicked(MouseEvent event)
	{
		System.out.println("Click!");	
	}

	//Go through and determine what the colors of the buttons should be
	public void prePaint()
	{
		Enumeration en = allProjects.keys();
		int origRed = 238;
		int origGreen = 238;
		int origBlue = 238;
		Color defaultColor = new Color(origRed,origGreen,origBlue);

		//Setup for each Project that is valid
		while(en.hasMoreElements())
		{
			String projName = (String)en.nextElement();
			Project projObj = null;

			projObj = allProjects.get(projName);

			if(projObj == null)
				continue;

			//Continue if it isn't valid
			if(! projObj.isValid())
				continue;

			if(projObj.isRunning())
			{
				projObj.getStartButton().setBackground(Color.green);
				projObj.getKillButton().setBackground(Color.blue);
			}
			else
			{
				projObj.getStartButton().setBackground(defaultColor);
				projObj.getKillButton().setBackground(defaultColor);
			}

			if(projObj.isPaused())
				projObj.getPauseButton().setBackground(Color.yellow);
			else
				projObj.getPauseButton().setBackground(defaultColor);

			if(projObj.isStopped())
				projObj.getStopButton().setBackground(Color.red);
			else
				projObj.getStopButton().setBackground(defaultColor);
		}
		
		repaint();
	}
}
