#!/usr/bin/python
import serial
import serial.tools.list_ports
import sys
import time

def test_serial_port(port_name):
    print(f"\nTesting port: {port_name}")
    
    # List all port details
    ports = list(serial.tools.list_ports.comports())
    port_info = next((p for p in ports if p.device == port_name), None)
    
    if port_info:
        print("\nPort details:")
        print(f"Device: {port_info.device}")
        print(f"Name: {port_info.name}")
        print(f"Description: {port_info.description}")
        print(f"Hardware ID: {port_info.hwid}")
        print(f"USB details: {port_info.usb_info()}")
        print(f"USB Manufacturer: {port_info.manufacturer}")
        print(f"USB Product: {port_info.product}")
        print(f"Serial Number: {port_info.serial_number}")
    else:
        print(f"No detailed info found for {port_name}")
    
    try:
        # Try different baud rates
        for baud in [9600, 19200, 38400, 57600, 115200]:
            print(f"\nTrying baud rate: {baud}")
            ser = serial.Serial(
                port=port_name,
                baudrate=baud,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=1,
                xonxoff=True
            )
            
            if ser.is_open:
                print(f"Successfully opened at {baud} baud")
                print(f"Port settings: {ser.get_settings()}")
                
                # Clear buffers
                ser.reset_input_buffer()
                ser.reset_output_buffer()
                
                # Try to write simple poll command
                test_msg = bytearray([0x02, 0x00, 0x01, 0xFE, 0xFF])
                print(f"Sending test message: {[hex(x) for x in test_msg]}")
                ser.write(test_msg)
                
                # Wait for response
                time.sleep(0.5)
                if ser.in_waiting:
                    resp = ser.read(ser.in_waiting)
                    print(f"Received {len(resp)} bytes: {[hex(x) for x in resp]}")
                else:
                    print("No response received")
                
                ser.close()
                print("Port closed")
            
    except Exception as e:
        print(f"Error: {str(e)}")
        
if __name__ == "__main__":
    print("Available ports:")
    ports = list(serial.tools.list_ports.comports())
    for port in ports:
        print(f"{port.device}: {port.description}")
    
    test_serial_port('/dev/ttyUSB0')