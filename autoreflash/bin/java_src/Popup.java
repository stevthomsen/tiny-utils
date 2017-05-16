import java.awt.*;
import java.awt.event.*;
import java.applet.*;
import javax.swing.BoxLayout;

public class Popup extends Applet 
{

	public static String yes = "Continue/Yes";
	public static String no = "Quit/No";
	public static String title = "No title set";
	public static String msg = "No message set";
	public static Button yesButton = null;

    public void init()
    {
		// Our two containers
		Container everythingContainer = new Container();
		Container textContainer = new Container();
		Container buttonContainer = new Container();

		// Only adding one text box and buttons to the containers
		// so flowlayout is fine
		buttonContainer.setLayout(new FlowLayout(FlowLayout.CENTER,10,10));
		textContainer.setLayout(new FlowLayout(FlowLayout.CENTER,10,10));

		// But need to arrange the layout of the containers to sit on top
		// of eachother
		setLayout(new FlowLayout(FlowLayout.CENTER,10,10));
		everythingContainer.setLayout(new BoxLayout(everythingContainer,BoxLayout.Y_AXIS));

		//All our components
		TextArea text = new TextArea(msg,10,50,TextArea.SCROLLBARS_VERTICAL_ONLY);
		text.setEditable(false);
		textContainer.add(text);
        yesButton = new Button(yes);

        buttonContainer.add(yesButton);
		Button noButton = new Button(no);
        buttonContainer.add(noButton);

		textContainer.validate();
		buttonContainer.validate();
		everythingContainer.validate();

		//Add containers to window
		everythingContainer.add(textContainer);
		everythingContainer.add(buttonContainer);
		add(everythingContainer);

		validate();
    }


    public void paint(Graphics g)
    {
		//No graphics to paint
    }

    public boolean action(Event evt, Object arg)
    {

        if (arg.equals(yes))
            System.exit(0);
        else if (arg.equals(no))
            System.exit(1);

        return true;
    }

    public static void main(String args[])
    {

		if(args.length == 1)
		{
			// The arg is the message to post, no title set
			msg = args[0];
		}
		else if(args.length > 1)
		{
			title = args[0];
			msg = "";
			for (int i=1; i<args.length; i++)
			{
				msg += args[i]+" ";
			}
		}

        Popup app = new Popup();
        Frame frame = new Frame(title);

        app.init();
        app.start();

        frame.add("Center", app);
		frame.setLocation(0,0);
        frame.resize(300, 200);
		frame.pack();

		//Set the yes button to focus
		yesButton.requestFocusInWindow();

        frame.show();
    }
}
