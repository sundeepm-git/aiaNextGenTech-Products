import { NextResponse } from 'next/server';
import path from 'path';
import { writeFile } from 'fs/promises';

export async function POST(request) {
  const formData = await request.formData();
  const file = formData.get('file');

  if (!file) {
    return NextResponse.json({ error: "No files received." }, { status: 400 });
  }

  const buffer = Buffer.from(await file.arrayBuffer());
  const filename = file.name.replaceAll(" ", "_");
  
  try {
    const cwd = process.cwd();
    // Saving to public/img so it is accessible via URL
    const uploadDir = path.join(cwd, "public/img"); 
    const filePath = path.join(uploadDir, filename);
    
    await writeFile(filePath, buffer);
    
    return NextResponse.json({ 
      Message: "Success", 
      status: 201, 
      path: `/img/${filename}` 
    });
  } catch (error) {
    console.error("Error occurred ", error);
    return NextResponse.json({ Message: "Failed", status: 500 });
  }
}
