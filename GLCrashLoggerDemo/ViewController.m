//
//  ViewController.m
//  GLCrashLoggerDemo
//
//  Created by Praveen Jha on 08/01/13.
//
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    UIButton *btn = [[UIButton alloc] initWithFrame:CGRectMake(0, self.view.frame.size.height/2, self.view.frame.size.width, 100)];
    [btn setTitle:@"Click to crash and check under </Application Support/iPhone Simulator/6.0/Applications/<Your App Hash>/Library/Caches/crashes/>" forState:UIControlStateNormal];
    [btn addTarget:self action:@selector(clickedToCrash:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    [btn setBackgroundColor:[UIColor orangeColor]];
	// Do any additional setup after loading the view, typically from a nib.
}

-(void)clickedToCrash:(id)sender
{
    [self performSelector:@selector(someNonExistingMethod)];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
