import java.lang.Boolean;
import javax.swing.JPanel;
import javax.swing.JButton;
import java.util.Hashtable;
import java.util.Set;
import java.util.List;
import java.util.Arrays;
import java.util.ArrayList;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.File;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.FileNotFoundException;
import java.io.IOException;

public class Project
{
	//Vars
	private Boolean isValid;
	private JPanel projPanel;
	private JButton startButton;
	private JButton stopButton;
	private JButton pauseButton;
	private JButton killButton;
	private JButton kermitButton;
	private String stopTime;
	private String defaultTTY;
	private Hashtable<String, String> ttys;

	//Constants
	private final String stopFile;
	private final String pauseFile;
	private final String pidFile;
	private final String serial;
	private final String project;
	private final String name;
	private final String id;
	private final File directory;

	public Project(File product_directory, String project, String id, String serial) throws IOException, FileNotFoundException
	{
		this.stopTime = "";
		this.project = project;
		this.id = id;
		this.serial = serial;
		this.name = project+"-"+serial;
		this.directory = product_directory;

		this.stopFile = "stop-"+serial;
		this.pauseFile = "pause-"+serial;
		this.pidFile = this.name+".pid";
		// need to check that directory is real...
		if (!this.directory.exists())
			throw new FileNotFoundException();
		if (!createPID(this.directory, this.pidFile))
			throw new IOException();
		this.ttys = new Hashtable<String,String>();
		System.out.println("Created object for "+this.name);
	}

	public Hashtable<String, String> getTTYs(){ return ttys; }
	public String getTTY(String key){ return ttys.get(key); }
	public boolean addTTY(String key, String tty)
	{
		if((new File(tty)).exists()) {
			if (ttys.isEmpty()){
				ttys.put(key, tty);
				setDefaultTTY(key);
			}else
				ttys.put(key,tty);
			return true;
		}
		System.out.println("Error: TTY "+tty+" does not exist!");
		return false;
	}

	public boolean setDefaultTTY(String key)
	{
		System.out.println("Attempting to set default TTY device to: "+key);
		if(ttys.get(key) == null)
			return false;
		defaultTTY = key;
		System.out.println("Set default TTY device to: "+key);
		return true;
	}

	public String getDefaultTTY()
	{
		if(defaultTTY != null && ttys.get(defaultTTY) == null){
			defaultTTY = null;
		}
		return defaultTTY;
	}

	public String getName()
	{
		return name;
	}

	private boolean createPID(File dest, String name)
	{
		File fpid = new File(dest, name);
		if (!createAndWriteFile(fpid, "", true)){
			System.out.println("Error: could not establish `"+name+"` file.");
			return false;
		}
		return true;
	}

	public String getPID()
	{
		return pidFile;
	}

	public JPanel getPanel(){ return projPanel;}
	public void setPanel(JPanel toSet)
	{
		projPanel = toSet;
	}

	public JButton getStartButton(){ return startButton;}
	public void setStartButton(JButton toSet)
	{
		startButton = toSet;
	}

	public JButton getStopButton(){ return stopButton;}
	public void setStopButton(JButton toSet)
	{
		stopButton = toSet;
	}

	public JButton getKillButton(){ return killButton;}
	public void setKillButton(JButton toSet)
	{
		killButton = toSet;
	}

	public JButton getKermitButton(){ return kermitButton;}
	public void setKermitButton(JButton toSet)
	{
		kermitButton = toSet;
	}

	public JButton getPauseButton(){ return pauseButton;}
	public void setPauseButton(JButton toSet)
	{
		pauseButton = toSet;
	}

	public boolean isRunning()
	{
		//Because isRunning checks to see
		// if there is still a PID running
		// it could be paused instead
		if(isPaused())
			return false;
		else if(isStopped())
			return false;

		//Find the .pid file
		File file = new File(directory,pidFile);
		if(!file.exists())
			return false;

		//Read and check the .pid file
		String line = readFile(file);

		if(line == null)
			return false;

		//Check to see if PID is still running
		return(checkRunning(line.split("\n")[0]));
	}

	public boolean isPaused()
	{
		File pause = new File(directory,pauseFile);
		
		if (pause.exists())
			return true;
		else
			return false;
	}

	public boolean isStopped()
	{
		File stop = new File(directory,stopFile);
		
		if (stop.exists())
			return true;
		else
			return false;
	}

	public boolean isValid()
	{
		if(isValid == null)
			isValid = new Boolean(validate());

		return isValid.booleanValue();
	}

	public boolean stop()
	{
		File stopFile2 = new File(directory,stopFile);

		if(!createAndWriteFile(stopFile2,""))
		{
			System.out.println("Removing stopfile");
			stopFile2.delete();
			return false;
		}
		return true;
	}

	public boolean kermit()
	{
		if(defaultTTY == null)
		{
			System.out.println("Error: no default TTY device defined.");
			return false;
		}

		try
		{
			System.out.println("Start kermit on device: "+ttys.get(defaultTTY));
			String[] pArr = {"/bin/sh","-c","/usr/bin/xterm -sl 4096 -e ./Kermit "+ttys.get(defaultTTY)+" & "};
			Process p = Runtime.getRuntime().exec(pArr);
		}
		catch(Exception e)
		{
			System.out.println("Error starting kermit");
			e.printStackTrace();
			return false;
		}
		return true;
	}

	public boolean kill()
	{
	 	if(isRunning())
		{
			//Find the .pid file
			File file = new File(directory,pidFile);

			if(!file.exists())
				return false;

			//Read and check the .pid file
			String line = readFile(file);
			
			if(line == null)
				return false;

			try
			{
				String[] pArr2 = {"/usr/bin/kill",line.split("\n")[0]};
				Process p = Runtime.getRuntime().exec(pArr2);
			}
			catch(Exception e)
			{
				System.err.println("Exception killing process:"+e);
			}	
			return true;
		}
		else
		{
			return false;
		}
	}

	public boolean start(String stop)
	{
		if(defaultTTY == null)
		{
			System.out.println("Error: no default TTY device defined.");
			return false;
		}

		stopTime = stop;

		try
		{
			String startup_log = "../config_dir/"+project+"/"+name+".startup_log";
			System.out.println("Start process on device: "+ttys.get(defaultTTY));
			// autoreflash.pl <package_dir> <pidFile> <product_id> <product_serial_num> <stop_time> <default_tty> [[NAME:TTY] [TTY] ..]
			List<String> arArr = new ArrayList<String>(Arrays.asList("/usr/bin/perl", "-x../",	"../autoreflash.pl", directory.toString(), pidFile.toString(), id, serial, stopTime, ttys.get(defaultTTY)));
			Set<String> keys = ttys.keySet();
			keys.remove(defaultTTY);
			for (String key: keys){	arArr.add(key+":"+ttys.get(key)); }

			// .join(args, " ")
			String args = "";
			for (String arg: arArr){ args += " "+arg; }

			String[] pArr = {"/bin/sh","-c", args.trim()+" > "+startup_log+" 2>&1 &"};
			System.exit(0);
			System.out.println(pArr.toString());
			Process p = Runtime.getRuntime().exec(pArr);
			String[] pArr2 = {"/bin/sh","-c","/usr/bin/xterm -T "+name+" -e /usr/bin/tail -f "+startup_log+" &"};
			p = Runtime.getRuntime().exec(pArr2);
		}
		catch(Exception e)
		{
			System.err.println("Exception starting process:"+e);
		}
		return true;
	}

	public boolean pause()
	{
		File pauseFile2 = new File(directory,pauseFile);

		if(!createAndWriteFile(pauseFile2,""))
		{
			System.out.println("Removing pause file");
			pauseFile2.delete();
			return false;
		}
		return true;
	}
	
	public boolean validate()
	{
		return true;
	}

	public boolean createAndWriteFile(File toCreate, String content){ return createAndWriteFile(toCreate, content, false); }
	public boolean createAndWriteFile(File toCreate, String content, boolean truncate)
	{
		FileWriter fw = null;
		BufferedWriter bw = null;

		try{
			//Problem creating file
			if(!toCreate.createNewFile() && !truncate)
				return false;

			//Open file and write content
			fw = new FileWriter(toCreate);
			bw = new BufferedWriter(fw);	
			bw.write(content);
		}catch(IOException e){
			e.printStackTrace();
			System.exit(1);
		}finally{
			if (bw != null){
				try { bw.close(); }
				catch(Exception e) { }
			}
			if (fw != null){
				try { fw.close(); }
				catch(Exception e) { }
			}
		}
		return true;
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

	public boolean checkRunning(String PID)
	{

		if(PID == null)
			return false;

		if(! (PID.length() > 0))
			return false;

		InputStreamReader stdInputIS = null;
		InputStreamReader stdErrorIS = null;
		BufferedReader stdInput = null;
		BufferedReader stdError = null;
		String s;

	        try
		{
			String[] pArr = {"/bin/sh","-c","/bin/ps -eo pid,cmd | /bin/grep 'perl' | /bin/grep -v 'grep' | /bin/grep 'autoreflash.pl' | /usr/bin/awk '{print $1}'"};
			Process p = Runtime.getRuntime().exec(pArr);

			stdInputIS = new InputStreamReader(p.getInputStream());
			stdErrorIS = new InputStreamReader(p.getErrorStream());
			stdInput = new BufferedReader(stdInputIS);
			stdError = new BufferedReader(stdErrorIS);

			// read the output from the command
			while ((s = stdInput.readLine()) != null) 
			{
				//System.out.println("FOUND PID: "+s);
				if (s.equals(PID))
					return true;
			}
            
			// read any errors from the attempted command
			while ((s = stdError.readLine()) != null)
			{
				System.out.println("ERROR:"+s);
			}

			return false;
		}
		catch (IOException e)
		{
			System.out.println("exception happened - here's what I know: ");
			e.printStackTrace();
			System.exit(1);
		}
		finally
		{
		
			// dispose all the resources after using them.
			if (stdError != null)
			{
				try { stdError.close(); }
				catch(Exception e) { }
			}
			if (stdInput != null)
			{
				try { stdInput.close(); }
				catch(Exception e) { }
			}
			if (stdErrorIS != null)
			{
				try { stdErrorIS.close(); }
				catch(Exception e) { }
			}
			if (stdInputIS != null)
			{
				try { stdInputIS.close(); }
				catch(Exception e) { }
			}
		}
		
		return false;

	}

	public String getStopTime()
	{
		return stopTime;
	}

	public static void killAll()
	{
		try
		{
			String[] pArr2 = {"/bin/sh","-c","/bin/ps -eo pid,cmd | /bin/grep 'perl' | /bin/grep 'autoreflash.pl' | /usr/bin/awk '{ print $1 }' | /usr/bin/xargs /usr/bin/kill -9 "};
			Process p = Runtime.getRuntime().exec(pArr2);
		}
		catch(Exception e)
		{
			System.err.println("ERROR IN KILLING ALL PROCESSES\n");
			e.printStackTrace();
		}
	}
}
